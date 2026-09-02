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

            // Determine if this is a huge request (entire file) – we must fetch it chunked
            let needsChunkedFetch = requestedLength <= 0 || requestedLength >= Int.max - 1 || Int64(requestedLength) > maxChunk * 2
            var combinedData = Data()
            var httpResponse: HTTPURLResponse?
            var totalLengthFromServer: Int64 = 0
            var mimeType: String?

            if needsChunkedFetch && !isProbe {
                // Fetch the huge range in 200KB chunks and combine (avoids 403 on 3M single Range)
                let originalLength = requestedLength
                let totalRequested = Int64(requestedLength)
                print("🔄 [ResourceLoader] Huge request \(originalLength) detected, fetching chunked 200KB")
                await MainActor.run { DebugLogger.shared.log("🔄 huge \(requestedOffset)-\(totalRequested) chunked") }
                var offset = requestedOffset
                var remaining = totalRequested
                // Cap total fetch to avoid infinite loop if AVPlayer requests Int.max
                let maxTotalFetch: Int64 = 4_000_000 // 4MB max for audio
                if remaining > maxTotalFetch || remaining <= 0 {
                    remaining = maxTotalFetch
                }
                while remaining > 0 {
                    let chunkEnd = min(offset + maxChunk - 1, requestedOffset + totalRequested - 1)
                    var chunkRequest = URLRequest(url: url)
                    chunkRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                    chunkRequest.setValue("*/*", forHTTPHeaderField: "Accept")
                    chunkRequest.setValue("bytes=\(offset)-\(chunkEnd)", forHTTPHeaderField: "Range")
                    print("🔄 [ResourceLoader] Chunk fetch bytes=\(offset)-\(chunkEnd)")
                    let (chunkData, chunkResponse) = try await URLSession.shared.data(for: chunkRequest)
                    guard let chunkHttp = chunkResponse as? HTTPURLResponse, (200...299).contains(chunkHttp.statusCode) || chunkHttp.statusCode == 206 else {
                        let code = (chunkResponse as? HTTPURLResponse)?.statusCode ?? -1
                        print("❌ [ResourceLoader] Chunk HTTP \(code)")
                        throw NSError(domain: "CustomResourceLoader", code: code)
                    }
                    if httpResponse == nil { httpResponse = chunkHttp as HTTPURLResponse }
                    if mimeType == nil { mimeType = chunkHttp.mimeType }
                    if totalLengthFromServer == 0, let cr = chunkHttp.value(forHTTPHeaderField: "Content-Range") {
                        let parts = cr.components(separatedBy: "/")
                        if parts.count == 2, let total = Int64(parts[1]) { totalLengthFromServer = total }
                    }
                    combinedData.append(chunkData)
                    let fetched = Int64(chunkData.count)
                    offset += fetched
                    remaining -= fetched
                    if fetched < maxChunk { break } // EOF
                    if combinedData.count >= totalRequested { break }
                }
                print("✅ [ResourceLoader] Chunked fetch done \(combinedData.count) bytes")
                await MainActor.run { DebugLogger.shared.log("✅ chunked \(combinedData.count) total=\(totalLengthFromServer)") }
                // Fall through to contentInfo and dataResponse handling with combinedData
                // We need to synthesize a HTTPURLResponse for later contentInfo
                // For now, use the last chunk's httpResponse
            } else {
                // Small probe or capped chunk – single request
                var request = URLRequest(url: url)
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("*/*", forHTTPHeaderField: "Accept")
                var fetchOffset = requestedOffset
                var fetchLength = requestedLength
                if !isProbe && fetchLength > maxChunk {
                    fetchLength = Int(maxChunk)
                }
                if fetchLength > 0 {
                    let rangeEnd = fetchOffset + Int64(fetchLength) - 1
                    request.setValue("bytes=\(fetchOffset)-\(rangeEnd)", forHTTPHeaderField: "Range")
                    print("🔄 [ResourceLoader] Requesting range: bytes=\(fetchOffset)-\(rangeEnd) (orig \(loadingRequest.dataRequest?.requestedLength ?? 0))")
                } else {
                    request.setValue("bytes=\(fetchOffset)-", forHTTPHeaderField: "Range")
                    print("🔄 [ResourceLoader] Requesting range: bytes=\(fetchOffset)-")
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
            let httpResponse = httpResponseUnwrapped

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [ResourceLoader] Not an HTTP response")
                loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: -1))
                return
            }

            print("✅ [ResourceLoader] Got response: \(httpResponse.statusCode)")
            print("✅ [ResourceLoader] Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")
            print("✅ [ResourceLoader] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            await MainActor.run { DebugLogger.shared.log("✅ loader HTTP \(httpResponse.statusCode) len=\(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "?")") }

            guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
                print("❌ [ResourceLoader] HTTP error: \(httpResponse.statusCode)")
                await MainActor.run { DebugLogger.shared.log("❌ loader HTTP \(httpResponse.statusCode) url=\(url.absoluteString.prefix(80))") }
                loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: httpResponse.statusCode))
                return
            }

            // Fill in content information – prioritize Content-Range total over Content-Length (chunk size)
            if let contentInfoRequest = loadingRequest.contentInformationRequest {
                // Use proper UTI for AVFoundation, not raw mimeType with codecs
                // googlevideo returns audio/mp4 but AVFoundation expects public.mpeg-4-audio / com.apple.quicktime-movie
                let uti: String
                if let mime = httpResponse.mimeType, mime.contains("audio") {
                    uti = "public.mpeg-4-audio"
                } else if let mime = httpResponse.mimeType, mime.contains("video") {
                    uti = "public.mpeg-4"
                } else {
                    uti = httpResponse.mimeType ?? "public.mpeg-4"
                }
                contentInfoRequest.contentType = uti
                await MainActor.run { DebugLogger.shared.log("📄 contentType UTI=\(uti) mime=\(httpResponse.mimeType ?? "?")") }

                // Get total content length – MUST use Content-Range for 206 responses
                var contentLength: Int64 = 0
                if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                    // Parse "bytes 0-999/1718053" format
                    let components = contentRange.components(separatedBy: "/")
                    if components.count == 2, let total = Int64(components[1]) {
                        contentLength = total
                    }
                }
                if contentLength == 0, let contentLengthString = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                   let length = Int64(contentLengthString) {
                    contentLength = length
                    // If we only have Content-Length for a Range request, it's the chunk size, not total
                    // Try to infer total from Content-Range if available, otherwise keep chunk size as fallback
                }

                contentInfoRequest.contentLength = contentLength
                contentInfoRequest.isByteRangeAccessSupported = true
                print("✅ [ResourceLoader] Content info: length=\(contentLength), type=\(mimeType ?? "nil")")
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
