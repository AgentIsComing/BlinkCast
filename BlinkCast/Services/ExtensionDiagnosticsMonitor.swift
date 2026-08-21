import Foundation

@MainActor
final class BlinkCastExtensionDiagnosticsMonitor {
    static let shared = BlinkCastExtensionDiagnosticsMonitor()

    private let appGroupID = "group.JaysApps.BlinkCast"
    private let logFileName = "blinkcast-extension-diagnostics.log"

    private var timer: Timer?
    private var mirroredLineCount = 0
    private var sawExtensionLog = false
    private var awaitToken = UUID()

    private init() {}

    func beginAwaitingExtensionLogs() {
        startIfNeeded()
        resetSharedLog()
        mirroredLineCount = 0
        sawExtensionLog = false

        let token = UUID()
        awaitToken = token

        NSLog("BlinkCast DIAGNOSTIC awaiting shared extension logs")

        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(12))
            } catch {
                return
            }

            guard let self,
                  self.awaitToken == token,
                  !self.sawExtensionLog else {
                return
            }

            NSLog("BlinkCast DIAGNOSTIC no shared extension logs after 12s; ReplayKit likely did not launch the broadcast extension process")
        }
    }

    private func startIfNeeded() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(
            withTimeInterval: 0.75,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pollSharedLog()
            }
        }

        RunLoop.main.add(timer!, forMode: .common)
        NSLog("BlinkCast DIAGNOSTIC shared extension log monitor started")
    }

    private func resetSharedLog() {
        guard let logURL else {
            NSLog("BlinkCast DIAGNOSTIC shared log URL unavailable during reset")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: logURL, options: .atomic)
            NSLog("BlinkCast DIAGNOSTIC reset shared extension log file")
        } catch {
            NSLog("BlinkCast DIAGNOSTIC failed to reset shared log: \(error.localizedDescription)")
        }
    }

    private func pollSharedLog() {
        guard let logURL else { return }
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        if lines.count < mirroredLineCount {
            mirroredLineCount = 0
        }

        guard mirroredLineCount < lines.count else { return }

        let newLines = lines[mirroredLineCount...]
        mirroredLineCount = lines.count

        for line in newLines {
            if line.contains("BlinkCast EXTENSION") {
                sawExtensionLog = true
            }
            NSLog("%@", line)
        }
    }

    private var logURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(logFileName, isDirectory: false)
    }
}