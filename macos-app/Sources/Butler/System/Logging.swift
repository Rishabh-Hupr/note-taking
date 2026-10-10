import Foundation

// butlerDataDir resolves the Butler data directory the same way the Go sidecar
// does: $BUTLER_DATA_DIR, else ~/.butler. Both the UI log and the sidecar's
// redirected stderr (app.log) live under here.
func butlerDataDir() -> String {
    if let d = ProcessInfo.processInfo.environment["BUTLER_DATA_DIR"], !d.isEmpty {
        return d
    }
    return (NSHomeDirectory() as NSString).appendingPathComponent(".butler")
}

// uiLog writes a timestamped line to the app's stderr, which the launch script
// captures into butler-ui.log. The sidecar's own stderr is redirected to app.log
// (see SidecarClient), so UI-side events (requests sent, responses received) stay
// separate from backend logs.
private let uiLogFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func uiLog(_ message: String) {
    let line = "\(uiLogFormatter.string(from: Date())) \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}
