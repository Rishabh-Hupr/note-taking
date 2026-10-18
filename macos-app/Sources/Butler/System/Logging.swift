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

// uiLog writes a timestamped line to butler-ui.log (size-rotated, see
// RotatingLogFile). The sidecar's own stderr is redirected to app.log
// (see SidecarClient), so UI-side events (requests sent, responses received) stay
// separate from backend logs.
private let uiLogFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

// The app's UI log, rotated like the backend's app.log and installed as stderr.
private let uiLogFile = RotatingLogFile(
    path: (butlerDataDir() as NSString).appendingPathComponent("butler-ui.log"),
    redirectStderr: true)

/// Call first thing at launch, so even early NSLog/crash output goes to the
/// rotating log rather than wherever the launcher pointed stderr.
func installUILog() { _ = uiLogFile }

func uiLog(_ message: String) {
    uiLogFile.write("\(uiLogFormatter.string(from: Date())) \(message)\n")
}
