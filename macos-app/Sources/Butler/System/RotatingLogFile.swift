import Foundation

/// An append-only log file that rotates by size, matching the Go backend's
/// app.log scheme: once the file reaches `maxBytes` it becomes `<path>.1`, older
/// backups shift up (.1 → .2 → .3) and the oldest beyond `keep` is removed, so it
/// never grows past roughly (keep + 1) × maxBytes. Created readable only by you.
///
/// With `redirectStderr`, the file is installed as the process's stderr and
/// stdout, so NSLog, print and crash output land in it too (and count toward the size).
final class RotatingLogFile: @unchecked Sendable {
    static let defaultMaxBytes = 1 << 20 // 1MB, same as the backend
    static let defaultKeep = 3

    let path: String
    private let maxBytes: Int
    private let keep: Int
    private let redirectStderr: Bool
    private let lock = NSLock() // uiLog is called from several threads
    private var fd: Int32 = -1
    // Bytes in the current file: read once when it's opened, then advanced by each
    // write, so writing never costs an extra fstat. Output written to the redirected
    // stderr by other code (NSLog, crashes) isn't counted until the next reopen.
    private var size: Int = 0
    // After a failed reopen, stop trying to rotate for a while: otherwise every
    // write would see the same oversized file and rotate again, wiping the backups.
    private var rotationPausedUntil = Date.distantPast

    init(path: String, maxBytes: Int = defaultMaxBytes, keep: Int = defaultKeep, redirectStderr: Bool) {
        self.path = path
        self.maxBytes = maxBytes
        self.keep = keep
        self.redirectStderr = redirectStderr
        openFile()
    }

    func write(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        if size >= maxBytes, Date() >= rotationPausedUntil {
            rotate()
        }
        let bytes = Array(text.utf8)
        let written = bytes.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
        if written > 0 { size += written }
    }

    private func rotate() {
        unlink("\(path).\(keep)")
        for i in stride(from: keep - 1, through: 1, by: -1) {
            rename("\(path).\(i)", "\(path).\(i + 1)")
        }
        rename(path, "\(path).1")
        if !openFile() {
            // Couldn't start a fresh file (e.g. dir unwritable): put the current one
            // back so we keep logging somewhere sensible, and retry later.
            rename("\(path).1", path)
            rotationPausedUntil = Date().addingTimeInterval(60)
        }
    }

    @discardableResult
    private func openFile() -> Bool {
        let newFD = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard newFD >= 0 else { return false }
        fchmod(newFD, 0o600) // also tighten a log created before logs were private
        var info = stat()
        size = fstat(newFD, &info) == 0 ? Int(info.st_size) : 0
        if redirectStderr {
            // Atomically repoint stderr and stdout at the fresh file.
            dup2(newFD, STDERR_FILENO)
            dup2(newFD, STDOUT_FILENO)
            close(newFD)
            fd = STDERR_FILENO
        } else {
            if fd >= 0 { close(fd) }
            fd = newFD
        }
        return true
    }
}
