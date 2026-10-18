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

    @Test func newLogIsPrivate() throws {
        let path = tempLog()
        _ = RotatingLogFile(path: path, redirectStderr: false)
        let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }
}
