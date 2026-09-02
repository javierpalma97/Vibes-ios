import Foundation
import Combine

@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    @Published var logs: [String] = []
    private let maxLogs = 500
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    func log(_ message: String) {
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] \(message)"
        print(line)
        logs.append(line)
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
    }

    func clear() {
        logs.removeAll()
    }

    var fullLog: String {
        logs.joined(separator: "\n")
    }
}
