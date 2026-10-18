import Foundation
import Testing
@testable import Butler

@Suite struct RotatingLogFileTests {
    private func tempLog() -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("butler-log-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("butler-ui.log").path
    }
    private func read(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

    @Test func appendsBelowTheLimit() {
        let path = tempLog()
        let log = RotatingLogFile(path: path, maxBytes: 100, keep: 3, redirectStderr: false)
        log.write("a\n"); log.write("b\n")
        #expect(read(path) == "a\nb\n")
        #expect(read(path + ".1") == nil)
    }

    @Test func rotatesAtTheLimitAndKeepsOnlyN() {
        let path = tempLog()
        let log = RotatingLogFile(path: path, maxBytes: 10, keep: 3, redirectStderr: false)
        // Each 10-byte write fills the file, so every next write rotates first.
        for n in 0..<6 { log.write(String(repeating: "\(n)", count: 9) + "\n") }
        #expect(read(path) == "555555555\n")
        #expect(read(path + ".1") == "444444444\n")
        #expect(read(path + ".2") == "333333333\n")
        #expect(read(path + ".3") == "222222222\n")
        #expect(read(path + ".4") == nil) // older ones dropped
    }

    @Test func failedRotationLosesNothing() throws {
        // The directory becomes unwritable at rotation time: the full log and every
        // backup must stay as they were, and logging must carry on.
        let path = tempLog()
        let dir = (path as NSString).deletingLastPathComponent
        for (suffix, text) in [(".1", "one"), (".2", "two"), (".3", "three")] {
            try text.write(toFile: path + suffix, atomically: false, encoding: .utf8)
        }
        let log = RotatingLogFile(path: path, maxBytes: 10, keep: 3, redirectStderr: false)
        log.write("0123456789") // reaches the limit
        chmod(dir, 0o500)
        defer { chmod(dir, 0o700) }
        log.write("still logging\n")
        chmod(dir, 0o700)
        #expect(read(path + ".1") == "one")
        #expect(read(path + ".2") == "two")
        #expect(read(path + ".3") == "three")
        #expect(read(path)?.contains("still logging") == true)
    }

    @Test func recoversWhenTheLogIsDeletedByHand() {
        let path = tempLog()
        let log = RotatingLogFile(path: path, recheckInterval: 0, redirectStderr: false)
        log.write("before\n")
        unlink(path)
        log.write("after\n")
        #expect(read(path) == "after\n")
    }

    @Test func unopenableLogFallsBackInsteadOfDroppingLines() {
        // Data dir missing: writes go to the existing stderr (no crash, nothing created).
        let path = "/nonexistent-butler-dir-\(UUID().uuidString)/butler-ui.log"
        let log = RotatingLogFile(path: path, redirectStderr: false)
        log.write("")
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func newLogIsPrivate() throws {
        let path = tempLog()
        _ = RotatingLogFile(path: path, redirectStderr: false)
        let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }
}
