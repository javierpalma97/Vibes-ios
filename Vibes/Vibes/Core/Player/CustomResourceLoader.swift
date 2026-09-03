import Foundation
import AVFoundation

class CustomResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let userAgent: String
    private var pendingRequests: [AVAssetResourceLoadingRequest] = []

    init(userAgent: String) {
        self.userAgent = userAgent
        super.init()
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else {
            print("❌ [ResourceLoader] No URL in request")
            Task { await MainActor.run { DebugLogger.shared.log("❌ loader no url") } }
            return false
        }

        // Convert custom scheme back to https
        var urlString = url.absoluteString
        if urlString.hasPrefix("customscheme://") {
            urlString = urlString.replacingOccurrences(of: "customscheme://", with: "https://")
        }

        guard let actualURL = URL(string: urlString) else {
            print("❌ [ResourceLoader] Failed to convert URL")
            return false
        }

        print("🔄 [ResourceLoader] Loading resource: \(actualURL.host ?? "unknown")")
        print("🔄 [ResourceLoader] Byte range: \(loadingRequest.dataRequest?.requestedOffset ?? 0) - \(loadingRequest.dataRequest?.requestedLength ?? 0)")
        Task { await MainActor.run { DebugLogger.shared.log("🔄 loader \(actualURL.host ?? "?") range \(loadingRequest.dataRequest?.requestedOffset ?? 0)-\(loadingRequest.dataRequest?.requestedLength ?? 0)") } }

        // Handle the request asynchronously
        Task {
            await handleLoadingRequest(loadingRequest, url: actualURL)
        }

        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        print("🔄 [ResourceLoader] Request cancelled")
        pendingRequests.removeAll { $0 == loadingRequest }
    }

    private func handleLoadingRequest(_ loadingRequest: AVAssetResourceLoadingRequest, url: URL) async {
        do {
            // Handle byte range request – cap to avoid YouTube 403 on huge ranges (>400KB for IOS)
            // Tests: ANDROID 139 200KB sequential full OK, 256KB IOS fails at 256k, 500KB fails. 200KB is safest.
            let maxChunk: Int64 = 200_000
            var requestedOffset: Int64 = 0
            var requestedLength: Int = 0
            var isProbe = false
            if let dataRequest = loadingRequest.dataRequest {
                requestedOffset = dataRequest.requestedOffset
                requestedLength = dataRequest.requestedLength

                // If this is a tiny probe (2 bytes), request a larger chunk instead
                if requestedLength == 2 && requestedOffset == 0 {
                    print("🔄 [ResourceLoader] Tiny probe detected, requesting 32KB instead")
                    requestedLength = 32768  // 32KB
                    isProbe = true
                }
            }

            // Para googlevideo con auth (WEB_REMIX), mandar Cookie + SAPISIDHASH (si no, 403 len=0 como en tu log vutbVGewIcg con webRemix)
            let authCookies = await MainActor.run { InnerTubeClient.shared.currentCookies }
            let authHeader = await MainActor.run { () -> String? in
                // Genera SAPISIDHASH igual que InnerTubeClient para googlevideo con WEB_REMIX
                guard let cookies = InnerTubeClient.shared.currentCookies else { return nil }
                // Usa el mismo helper que InnerTubeClient (duplicado aquí para no exponer generate)
                let map = cookies.split(separator: ";").reduce(into: [String:String]()) { res, part in
                    let t = part.trimmingCharacters(in: .whitespaces)
                    if let eq = t.firstIndex(of: "=") {
                        res[String(t[..<eq])] = String(t[t.index(after: eq)...])
                    }
                }
                let sid = map["SAPISID"] ?? map["__Secure-3PAPISID"] ?? map["__Secure-3PSID"]
                guard let s = sid, !s.isEmpty else { return nil }
                let ts = Int(Date().timeIntervalSince1970)
                let origin = "https://music.youtube.com"
                let input = "\(ts) \(s) \(origin)"
                guard let d = input.data(using: .utf8) else { return nil }
                var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                d.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(d.count), &digest) }
                let hash = digest.map { String(format: "%02hhx", $0) }.joined()
                return "SAPISIDHASH \(ts)_\(hash)"
            }

            // Huge requests (AVPlayer pide 0-3M) no deben fetchear todo el fichero → lento y 403 tras 1M.
            // Solo devolvemos el primer maxChunk (200KB) y dejamos que AVPlayer pida el resto secuencialmente.
            let isHuge = requestedLength <= 0 || requestedLength >= Int.max - 1 || Int64(requestedLength) > maxChunk * 2
            var combinedData = Data()
            var httpResponse: HTTPURLResponse?
            var totalLengthFromServer: Int64 = 0
            var mimeType: String?

            if isHuge && !isProbe {
                let originalLength = requestedLength
                print("🔄 [ResourceLoader] Huge \(requestedOffset)-\(originalLength) → cap \(maxChunk) para fluidez")
                await MainActor.run { DebugLogger.shared.log("🔄 huge \(requestedOffset)-\(originalLength) cap \(maxChunk)") }
                // Solo primer chunk, no todo el fichero
                var fetchOffset = requestedOffset
                var fetchLength = Int(maxChunk)
                var chunkData: Data = Data()
                var chunkHttp: HTTPURLResponse?
                var lastError: Error?
                for attempt in 0..<2 {
                    var chunkRequest: URLRequest
                    if attempt == 0 {
                        chunkRequest = URLRequest(url: url)
                        chunkRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                        chunkRequest.setValue("*/*", forHTTPHeaderField: "Accept")
                        if let ck = authCookies { chunkRequest.setValue(ck, forHTTPHeaderField: "Cookie") }
                        if let ah = authHeader { chunkRequest.setValue(ah, forHTTPHeaderField: "Authorization") }
                        chunkRequest.setValue("bytes=\(fetchOffset)-\(fetchOffset+Int64(fetchLength)-1)", forHTTPHeaderField: "Range")
                        print("🔄 [ResourceLoader] Huge cap fetch bytes=\(fetchOffset)-\(fetchOffset+Int64(fetchLength)-1) (header) ck=\(authCookies != nil) ah=\(authHeader != nil)")
                    } else {
                        let sep = url.absoluteString.contains("?") ? "&" : "?"
                        let qUrlString = url.absoluteString + "\(sep)range=\(fetchOffset)-\(fetchOffset+Int64(fetchLength)-1)"
                        guard let qUrl = URL(string: qUrlString) else { throw NSError(domain: "CustomResourceLoader", code: -2) }
                        chunkRequest = URLRequest(url: qUrl)
                        chunkRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                        chunkRequest.setValue("*/*", forHTTPHeaderField: "Accept")
                        if let ck = authCookies { chunkRequest.setValue(ck, forHTTPHeaderField: "Cookie") }
                        if let ah = authHeader { chunkRequest.setValue(ah, forHTTPHeaderField: "Authorization") }
                        print("🔄 [ResourceLoader] Huge fallback query")
                    }
                    do {
                        let (data, response) = try await URLSession.shared.data(for: chunkRequest)
                        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 206 else {
                            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                            print("❌ [ResourceLoader] Huge HTTP \(code) attempt \(attempt)")
                            lastError = NSError(domain: "CustomResourceLoader", code: code)
                            continue
                        }
                        chunkData = data
                        chunkHttp = http as HTTPURLResponse
                        lastError = nil
                        break
                    } catch {
                        lastError = error
                        print("❌ [ResourceLoader] Huge error \(error) attempt \(attempt)")
                    }
                }
                guard let http = chunkHttp else { throw lastError ?? NSError(domain: "CustomResourceLoader", code: -1) }
                httpResponse = http
                mimeType = http.mimeType
                if let cr = http.value(forHTTPHeaderField: "Content-Range") {
                    let parts = cr.components(separatedBy: "/")
                    if parts.count == 2, let total = Int64(parts[1]) { totalLengthFromServer = total }
                }
                combinedData = chunkData
                print("✅ [ResourceLoader] Huge cap done \(combinedData.count) total=\(totalLengthFromServer)")
                await MainActor.run { DebugLogger.shared.log("✅ huge cap \(combinedData.count) total=\(totalLengthFromServer)") }
            } else {
                // Small probe or capped chunk – single request
                var request = URLRequest(url: url)
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("*/*", forHTTPHeaderField: "Accept")
                if let ck = authCookies { request.setValue(ck, forHTTPHeaderField: "Cookie") }
                if let ah = authHeader { request.setValue(ah, forHTTPHeaderField: "Authorization") }
                var fetchOffset = requestedOffset
                var fetchLength = requestedLength
                if !isProbe && fetchLength > maxChunk {
                    fetchLength = Int(maxChunk)
                }
                if fetchLength > 0 {
                    let rangeEnd = fetchOffset + Int64(fetchLength) - 1
                    request.setValue("bytes=\(fetchOffset)-\(rangeEnd)", forHTTPHeaderField: "Range")
                    print("🔄 [ResourceLoader] Requesting range: bytes=\(fetchOffset)-\(rangeEnd) (orig \(loadingRequest.dataRequest?.requestedLength ?? 0)) ck=\(authCookies != nil) ah=\(authHeader != nil)")
                } else {
                    request.setValue("bytes=\(fetchOffset)-", forHTTPHeaderField: "Range")
                    print("🔄 [ResourceLoader] Requesting range: bytes=\(fetchOffset)- ck=\(authCookies != nil) ah=\(authHeader != nil)")
                }
                print("🔄 [ResourceLoader] Making request with default headers")
                print("🔄 [ResourceLoader] URL host: \(url.host ?? "unknown")")

                let (data, response) = try await URLSession.shared.data(for: request)
                combinedData = data
                httpResponse = response as? HTTPURLResponse
                mimeType = httpResponse?.mimeType
                if let cr = httpResponse?.value(forHTTPHeaderField: "Content-Range") {
                    let parts = cr.components(separatedBy: "/")
                    if parts.count == 2, let total = Int64(parts[1]) { totalLengthFromServer = total }
                }
                print("✅ [ResourceLoader] Got response: \(httpResponse?.statusCode ?? -1)")
                print("✅ [ResourceLoader] Content-Length: \(httpResponse?.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")
                await MainActor.run { DebugLogger.shared.log("✅ loader HTTP \(httpResponse?.statusCode ?? -1) len=\(httpResponse?.value(forHTTPHeaderField: "Content-Length") ?? "?")") }
            }

            guard let httpResponseUnwrapped = httpResponse else {
                print("❌ [ResourceLoader] Not an HTTP response")
                loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: -1))
                return
            }

            print("✅ [ResourceLoader] Got response: \(httpResponseUnwrapped.statusCode)")
            print("✅ [ResourceLoader] Content-Length: \(httpResponseUnwrapped.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")
            print("✅ [ResourceLoader] Content-Type: \(httpResponseUnwrapped.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            await MainActor.run { DebugLogger.shared.log("✅ loader HTTP \(httpResponseUnwrapped.statusCode) len=\(httpResponseUnwrapped.value(forHTTPHeaderField: "Content-Length") ?? "?")") }

            guard (200...299).contains(httpResponseUnwrapped.statusCode) || httpResponseUnwrapped.statusCode == 206 else {
                print("❌ [ResourceLoader] HTTP error: \(httpResponseUnwrapped.statusCode)")
                await MainActor.run { DebugLogger.shared.log("❌ loader HTTP \(httpResponseUnwrapped.statusCode) url=\(url.absoluteString.prefix(80))") }
                loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: httpResponseUnwrapped.statusCode))
                return
            }

            // Use combinedData and httpResponseUnwrapped from here on
            let data = combinedData
            let finalResponse = httpResponseUnwrapped

            // Fill in content information – prioritize Content-Range total over Content-Length (chunk size)
            if let contentInfoRequest = loadingRequest.contentInformationRequest {
                // Use proper UTI for AVFoundation, not raw mimeType with codecs
                // googlevideo returns audio/mp4 but AVFoundation expects public.mpeg-4-audio / com.apple.quicktime-movie
                let uti: String
                if let mime = finalResponse.mimeType, mime.contains("audio") {
                    uti = "public.mpeg-4-audio"
                } else if let mime = finalResponse.mimeType, mime.contains("video") {
                    uti = "public.mpeg-4"
                } else {
                    uti = finalResponse.mimeType ?? "public.mpeg-4"
                }
                contentInfoRequest.contentType = uti
                await MainActor.run { DebugLogger.shared.log("📄 contentType UTI=\(uti) mime=\(finalResponse.mimeType ?? "?")") }

                // Get total content length – MUST use Content-Range for 206 responses
                var contentLength: Int64 = 0
                if let contentRange = finalResponse.value(forHTTPHeaderField: "Content-Range") {
                    // Parse "bytes 0-999/1718053" format
                    let components = contentRange.components(separatedBy: "/")
                    if components.count == 2, let total = Int64(components[1]) {
                        contentLength = total
                    }
                }
                if contentLength == 0, let contentLengthString = finalResponse.value(forHTTPHeaderField: "Content-Length"),
                   let length = Int64(contentLengthString) {
                    contentLength = length
                }
                // Fallback to totalLengthFromServer if still 0
                if contentLength == 0 { contentLength = totalLengthFromServer }

                contentInfoRequest.contentLength = contentLength
                contentInfoRequest.isByteRangeAccessSupported = true
                print("✅ [ResourceLoader] Content info: length=\(contentLength), type=\(mimeType ?? finalResponse.mimeType ?? "nil")")
            }

            // Provide the data - only the amount originally requested
            if let dataRequest = loadingRequest.dataRequest {
                let originalRequestedLength = dataRequest.requestedLength

                // Only respond with the originally requested amount
                if data.count > originalRequestedLength {
                    let trimmedData = data.prefix(originalRequestedLength)
                    dataRequest.respond(with: Data(trimmedData))
                    print("✅ [ResourceLoader] Responded with \(trimmedData.count) bytes (trimmed from \(data.count))")
                } else {
                    dataRequest.respond(with: data)
                    print("✅ [ResourceLoader] Responded with \(data.count) bytes")
                }
            }

            loadingRequest.finishLoading()
            print("✅ [ResourceLoader] Request finished successfully")

        } catch {
            print("❌ [ResourceLoader] Error: \(error)")
            await MainActor.run { DebugLogger.shared.log("❌ loader error \(error.localizedDescription)") }
            loadingRequest.finishLoading(with: error)
        }
    }
}
