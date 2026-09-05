import Foundation

// YouTube Data API v3 con el Bearer OAuth2 de la app (scope `youtube`).
// Es la vía oficial para mutaciones de cuenta: Me gusta, playlists y perfil.
// InnerTube se sigue usando para catálogo/búsqueda/streaming.
// Cuota: lecturas ~1 unidad, escrituras (rate/insert/delete) ~50. De sobra para uso personal.

enum YouTubeDataError: Error, LocalizedError {
    case noAuth
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noAuth: return "Sin sesión OAuth"
        case .http(let code, let msg): return "DataAPI HTTP \(code): \(msg)"
        case .badResponse(let what): return "DataAPI respuesta inválida (\(what))"
        }
    }
}

struct YTChannelProfile {
    let title: String
    let avatarUrl: String?
    let handle: String?
}

struct YTDataPlaylist {
    let id: String
    let title: String
    let description: String?
    let itemCount: Int
    let thumbnailUrl: String?
}

struct YTDataPlaylistItem {
    let itemId: String
    let videoId: String
    let title: String
    let artists: String
    let thumbnailUrl: String?
    let position: Int
}

enum YTVideoRating: String {
    case like
    case dislike
    case none
}

/// Tarea pendiente de sincronizar en cloud (outbox con reintentos).
struct PendingCloudTask: Codable {
    enum Kind: String, Codable {
        case like
        case playlistAdd
        case playlistRemove
    }
    let id: String
    let kind: Kind
    let videoId: String
    let playlistId: String?
    let itemId: String?
    let liked: Bool?
    var attempts: Int
    let createdAt: Date
}

/// Sin ruta cloud posible (ni Data API ni sesión web): aparcar sin gastar intentos.
struct OutboxNoRoute: Error {}

final class YouTubeDataAPI {
    static let shared = YouTubeDataAPI()
    private let base = "https://www.googleapis.com/youtube/v3"
    private static let disabledKey = "ytDataApiDisabled"
    private init() {}

    /// El cliente OAuth público de TV (861556708454) no tiene Data API habilitada
    /// y Google no permite habilitarla: cuando se detecta el 403 se deja de intentar.
    static var isDisabled: Bool {
        UserDefaults.standard.bool(forKey: disabledKey)
    }

    // MARK: - HTTP

    private func token() throws -> String {
        guard let bearer = OAuthManager.bearerHeaderSync else { throw YouTubeDataError.noAuth }
        return bearer
    }

    private func call(path: String, method: String, query: [String: String], body: [String: Any]? = nil) async throws -> Any {
        var comps = URLComponents(string: base + path)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw YouTubeDataError.badResponse("url") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(try token(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else {
            var msg = "HTTP \(code)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let detail = err["message"] as? String {
                msg = "HTTP \(code): \(detail)"
            }
            await MainActor.run { DebugLogger.shared.log("❌ [DataAPI] \(method) \(path) → \(msg)") }
            if code == 403 && (msg.contains("has not been used") || msg.contains("disabled")) {
                UserDefaults.standard.set(true, forKey: Self.disabledKey)
                await MainActor.run { DebugLogger.shared.log("⛔️ [DataAPI] Deshabilitada en el proyecto OAuth: no se reintentará. Cloud solo vía sesión web.") }
            }
            throw YouTubeDataError.http(code, msg)
        }
        if data.isEmpty { return [String: Any]() }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw YouTubeDataError.badResponse("json")
        }
    }

    private func thumbUrl(_ snippet: [String: Any]) -> String? {
        let thumbs = snippet["thumbnails"] as? [String: Any]
        let pick = (thumbs?["medium"] ?? thumbs?["high"] ?? thumbs?["default"]) as? [String: Any]
        return pick?["url"] as? String
    }

    // MARK: - Canal / perfil

    func getMyChannel() async throws -> YTChannelProfile {
        let json = try await call(path: "/channels", method: "GET",
                                 query: ["part": "snippet", "mine": "true"]) as? [String: Any]
        guard let item = (json?["items"] as? [[String: Any]])?.first,
              let sn = item["snippet"] as? [String: Any],
              let title = sn["title"] as? String, !title.isEmpty else {
            throw YouTubeDataError.badResponse("channels")
        }
        return YTChannelProfile(title: title,
                                avatarUrl: thumbUrl(sn),
                                handle: sn["customUrl"] as? String)
    }

    // MARK: - Me gusta

    func rateVideo(id: String, rating: YTVideoRating) async throws {
        _ = try await call(path: "/videos/rate", method: "POST",
                           query: ["id": id, "rating": rating.rawValue])
    }

    /// rating por vídeo ("like"/"dislike"/"none"). Hasta 50 ids por llamada.
    func getRatings(ids: [String]) async throws -> [String: String] {
        var out: [String: String] = [:]
        for chunk in ids.chunkedBy(50) {
            let json = try await call(path: "/videos/getRating", method: "GET",
                                      query: ["id": chunk.joined(separator: ",")]) as? [String: Any]
            for item in (json?["items"] as? [[String: Any]]) ?? [] {
                if let vid = item["videoId"] as? String,
                   let rating = item["rating"] as? String {
                    out[vid] = rating
                }
            }
        }
        return out
    }

    /// Items con Me gusta (vía la playlist especial "likes" del canal).
    func getLikedItems(limit: Int = 500) async throws -> [YTDataPlaylistItem] {
        let json = try await call(path: "/channels", method: "GET",
                                  query: ["part": "contentDetails", "mine": "true"]) as? [String: Any]
        guard let item = (json?["items"] as? [[String: Any]])?.first,
              let cd = item["contentDetails"] as? [String: Any],
              let rel = cd["relatedPlaylists"] as? [String: Any],
              let likesId = rel["likes"] as? String, !likesId.isEmpty else {
            throw YouTubeDataError.badResponse("likes playlist")
        }
        return try await getPlaylistItems(playlistId: likesId, max: limit)
    }

    // MARK: - Playlists

    func getMyPlaylists() async throws -> [YTDataPlaylist] {
        var out: [YTDataPlaylist] = []
        var pageToken: String? = nil
        repeat {
            var query = ["part": "snippet,contentDetails", "mine": "true", "maxResults": "50"]
            if let token = pageToken { query["pageToken"] = token }
            let json = try await call(path: "/playlists", method: "GET", query: query) as? [String: Any]
            for item in (json?["items"] as? [[String: Any]]) ?? [] {
                guard let id = item["id"] as? String,
                      let sn = item["snippet"] as? [String: Any],
                      let title = sn["title"] as? String else { continue }
                let cd = item["contentDetails"] as? [String: Any]
                out.append(YTDataPlaylist(
                    id: id,
                    title: title,
                    description: sn["description"] as? String,
                    itemCount: cd?["itemCount"] as? Int ?? 0,
                    thumbnailUrl: thumbUrl(sn)
                ))
            }
            pageToken = (json?["nextPageToken"] as? String)?.isEmpty == false ? json?["nextPageToken"] as? String : nil
        } while pageToken != nil
        return out
    }

    func getPlaylistItems(playlistId: String, max: Int = 200) async throws -> [YTDataPlaylistItem] {
        var out: [YTDataPlaylistItem] = []
        var pageToken: String? = nil
        while out.count < max {
            var query = ["part": "snippet,contentDetails", "playlistId": playlistId, "maxResults": "50"]
            if let token = pageToken { query["pageToken"] = token }
            let json = try await call(path: "/playlistItems", method: "GET", query: query) as? [String: Any]
            for item in (json?["items"] as? [[String: Any]]) ?? [] {
                guard let itemId = item["id"] as? String,
                      let sn = item["snippet"] as? [String: Any],
                      let res = sn["resourceId"] as? [String: Any],
                      let videoId = res["videoId"] as? String else { continue }
                out.append(YTDataPlaylistItem(
                    itemId: itemId,
                    videoId: videoId,
                    title: sn["title"] as? String ?? "",
                    artists: sn["videoOwnerChannelTitle"] as? String ?? "",
                    thumbnailUrl: thumbUrl(sn),
                    position: sn["position"] as? Int ?? out.count
                ))
            }
            guard let next = json?["nextPageToken"] as? String, !next.isEmpty else { break }
            pageToken = next
        }
        return out
    }

    /// Añade un vídeo. Devuelve el playlistItem id (sirve para borrarlo después).
    func addVideoToPlaylist(playlistId: String, videoId: String) async throws -> String? {
        let body: [String: Any] = [
            "snippet": [
                "playlistId": playlistId,
                "resourceId": ["kind": "youtube#video", "videoId": videoId]
            ]
        ]
        let json = try await call(path: "/playlistItems", method: "POST",
                                  query: ["part": "snippet"], body: body) as? [String: Any]
        return json?["id"] as? String
    }

    func removeVideoFromPlaylist(itemId: String) async throws {
        _ = try await call(path: "/playlistItems", method: "DELETE", query: ["id": itemId])
    }

    func createPlaylist(title: String, description: String? = nil, privacy: String = "private") async throws -> String {
        var snippet: [String: Any] = ["title": title]
        if let description = description, !description.isEmpty { snippet["description"] = description }
        let body: [String: Any] = ["snippet": snippet, "status": ["privacyStatus": privacy]]
        let json = try await call(path: "/playlists", method: "POST",
                                  query: ["part": "snippet,status"], body: body) as? [String: Any]
        guard let id = json?["id"] as? String, !id.isEmpty else {
            throw YouTubeDataError.badResponse("create")
        }
        return id
    }

    func deletePlaylist(id: String) async throws {
        _ = try await call(path: "/playlists", method: "DELETE", query: ["id": id])
    }
}

private extension Array {
    func chunkedBy(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var out: [[Element]] = []
        var i = 0
        while i < count {
            out.append(Array(self[i..<Swift.min(i + size, count)]))
            i += size
        }
        return out
    }
}
