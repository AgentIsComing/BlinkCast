import Foundation

private enum BlinkCastSharedDiagnostics {
    static let appGroupID = "group.JaysApps.BlinkCast"
    static let logFileName = "blinkcast-extension-diagnostics.log"

    static func log(_ message: String) {
        NSLog("%@", message)

        guard let logURL else { return }

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            NSLog("BlinkCast EXTENSION ERROR shared log write failed: \(error.localizedDescription)")
        }
    }

    private static var logURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(logFileName, isDirectory: false)
    }
}

func blinkExtensionLog(_ message: String) {
    BlinkCastSharedDiagnostics.log(message)
}