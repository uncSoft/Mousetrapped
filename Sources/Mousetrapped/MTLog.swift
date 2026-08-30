import Foundation
import os

/// Logging: always goes to the unified log (subsystem
/// dev.mousetrapped.Mousetrapped; view with `log stream`). The file mirror
/// at ~/Library/Logs/Mousetrapped.log only exists when debugging is opted
/// in via `defaults write dev.mousetrapped.Mousetrapped debugLogging -bool true`.
enum MTLog {
    private static var fileLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debugLogging")
    }
    private static let logger = Logger(subsystem: "dev.mousetrapped.Mousetrapped",
                                       category: "app")
    private static let queue = DispatchQueue(label: "dev.mousetrapped.log")
    private static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Mousetrapped.log")
    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        guard fileLoggingEnabled else { return }
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
