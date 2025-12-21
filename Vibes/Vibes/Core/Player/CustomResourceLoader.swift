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
            var request = URLRequest(url: url)

            // Don't set ANY custom headers - let URLSession use defaults
            // request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            // Handle byte range request - but request more data for tiny probes
            if let dataRequest = loadingRequest.dataRequest {
                var requestedOffset = dataRequest.requestedOffset
                var requestedLength = dataRequest.requestedLength

                // If this is a tiny probe (2 bytes), request a larger chunk instead
                if requestedLength == 2 && requestedOffset == 0 {
                    print("🔄 [ResourceLoader] Tiny probe detected, requesting 32KB instead")
                    requestedLength = 32768  // 32KB
                }

                // Always add Range header
                if requestedLength > 0 && requestedLength < Int.max - 1 {
                    let rangeEnd = requestedOffset + Int64(requestedLength) - 1
                    request.setValue("bytes=\(requestedOffset)-\(rangeEnd)", forHTTPHeaderField: "Range")
                    print("🔄 [ResourceLoader] Requesting range: bytes=\(requestedOffset)-\(rangeEnd)")
                } else {
                    request.setValue("bytes=\(requestedOffset)-", forHTTPHeaderField: "Range")
                    print("🔄 [ResourceLoader] Requesting range: bytes=\(requestedOffset)-")
                }
            }

            print("🔄 [ResourceLoader] Making request with default headers")
            print("🔄 [ResourceLoader] URL host: \(url.host ?? "unknown")")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [ResourceLoader] Not an HTTP response")
                loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: -1))
                return
            }

            print("✅ [ResourceLoader] Got response: \(httpResponse.statusCode)")
            print("✅ [ResourceLoader] Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")
            print("✅ [ResourceLoader] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")

            guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
                print("❌ [ResourceLoader] HTTP error: \(httpResponse.statusCode)")
                loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: httpResponse.statusCode))
                return
            }

            // Fill in content information
            if let contentInfoRequest = loadingRequest.contentInformationRequest {
                let mimeType = httpResponse.mimeType
                if let mimeType = mimeType {
                    contentInfoRequest.contentType = mimeType
                }

                // Get content length
                var contentLength: Int64 = 0
                if let contentLengthString = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                   let length = Int64(contentLengthString) {
                    contentLength = length
                } else if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                    // Parse "bytes 0-999/1000" format
                    let components = contentRange.components(separatedBy: "/")
                    if components.count == 2, let total = Int64(components[1]) {
                        contentLength = total
                    }
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
            loadingRequest.finishLoading(with: error)
        }
    }
}
