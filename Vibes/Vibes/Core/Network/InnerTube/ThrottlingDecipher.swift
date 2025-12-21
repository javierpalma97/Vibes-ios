import Foundation
import JavaScriptCore

/// Handles YouTube's throttling `n` parameter by executing the player JS n-transform.
final class ThrottlingDecipher {
    static let shared = ThrottlingDecipher()

    private var cachedJsUrl: String?
    private var cachedJsCode: String?
    private var cachedContext: JSContext?
    private var cachedNFunction: String?

    private init() {}

    /// Returns a URL with a deobfuscated `n` parameter when possible.
    func deobfuscate(url: String, playerResponse: PlayerResponse?) async -> String {
        // Clean escaped separators from InnerTube (e.g. \u0026)
        let cleanUrl = url
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003d", with: "=")
            .replacingOccurrences(of: "\\/", with: "/")

        // Extract n using regex first (handles encoded separators)
        let regex = try? NSRegularExpression(pattern: #"[\?&]n=([^&]+)"#, options: [])
        let nsRange = NSRange(cleanUrl.startIndex..<cleanUrl.endIndex, in: cleanUrl)
        var nValue: String?
        if let match = regex?.firstMatch(in: cleanUrl, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: cleanUrl) {
            nValue = String(cleanUrl[range])
        }

        // If regex failed, fall back to manual query parsing
        var items = extractQueryItemsManually(from: cleanUrl)
        if nValue == nil, let idx = items.firstIndex(where: { $0.name == "n" }) {
            nValue = items[idx].value
        }

        guard let foundN = nValue else {
            return cleanUrl
        }

        // Ensure n param is in items
        if !items.contains(where: { $0.name == "n" }) {
            items.append(URLQueryItem(name: "n", value: foundN))
        }

        guard let jsUrl = playerResponse?.assets?.js else {
            return cleanUrl
        }

        do {
            try await prepare(jsUrl: jsUrl)
            guard let funcName = cachedNFunction,
                  let context = cachedContext,
                  let fn = context.objectForKeyedSubscript(funcName),
                  fn.isObject else {
                return cleanUrl
            }

            if let result = fn.call(withArguments: [nValue])?.toString() {
                if let idx = items.firstIndex(where: { $0.name == "n" }) {
                    items[idx] = URLQueryItem(name: "n", value: result)
                }
                let rebuilt = rebuildUrl(base: cleanUrl, items: items)
                return rebuilt
            }
        } catch {
            // Silently fail and return original URL
        }

        return cleanUrl
    }

    // MARK: - Preparation

    private func prepare(jsUrl: String) async throws {
        // Reuse cached context when same JS is used
        if cachedJsUrl == jsUrl, cachedContext != nil, cachedNFunction != nil {
            return
        }

        let jsCode = try await fetchJS(jsUrl: jsUrl)
        let nFunction = try extractNFunctionName(from: jsCode)

        guard let context = JSContext() else {
            throw ThrottlingError.contextInitFailed
        }

        // Make console.log available to avoid JS errors
        let consoleLog: @convention(block) (String) -> Void = { _ in }
        if let console = context.objectForKeyedSubscript("console") {
            console.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        } else {
            context.setObject(["log": consoleLog], forKeyedSubscript: "console" as NSString)
        }

        context.exceptionHandler = { _, _ in }

        context.evaluateScript(jsCode)

        cachedJsUrl = jsUrl
        cachedJsCode = jsCode
        cachedContext = context
        cachedNFunction = nFunction
    }

    private func fetchJS(jsUrl: String) async throws -> String {
        if let cached = cachedJsCode, cachedJsUrl == jsUrl {
            return cached
        }

        guard let url = URL(string: jsUrl) else {
            throw ThrottlingError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw ThrottlingError.httpError(code: http.statusCode)
        }

        guard let code = String(data: data, encoding: .utf8) else {
            throw ThrottlingError.decodeFailed
        }

        return code
    }

    // MARK: - Parsing

    private func extractNFunctionName(from js: String) throws -> String {
        // Pattern used by yt-dlp/NewPipe to find the n-transform function
        let pattern = #"\.get\("n"\)\)&&\(b=([A-Za-z0-9$]{2})\(b\)"#
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(js.startIndex..<js.endIndex, in: js)

        guard let match = regex.firstMatch(in: js, options: [], range: range),
              let nameRange = Range(match.range(at: 1), in: js) else {
            throw ThrottlingError.nFunctionNotFound
        }

        return String(js[nameRange])
    }

    // MARK: - Helpers

    private func extractQueryItemsManually(from url: String) -> [URLQueryItem] {
        guard let queryStart = url.firstIndex(of: "?") else { return [] }
        let queryString = url[url.index(after: queryStart)...]
        var items: [URLQueryItem] = []

        for part in queryString.split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let name = pair[0]
            let value = pair[1]
            items.append(URLQueryItem(name: name, value: value))
        }

        return items
    }

    private func rebuildUrl(base: String, items: [URLQueryItem]) -> String {
        guard let qIndex = base.firstIndex(of: "?") else {
            let query = items.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            return base + "?" + query
        }

        let prefix = String(base[..<qIndex])
        let query = items.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        return prefix + "?" + query
    }
}

// MARK: - Errors

enum ThrottlingError: Error {
    case invalidUrl
    case httpError(code: Int)
    case decodeFailed
    case nFunctionNotFound
    case contextInitFailed
}
