import Foundation

/// An append-only log file that rotates by size, matching the Go backend's
/// app.log scheme: once the file reaches `maxBytes` it becomes `<path>.1`, older
/// backups shift up (.1 → .2 → .3) and the oldest beyond `keep` is removed, so it
/// never grows past roughly (keep + 1) × maxBytes. Created readable only by you.
///
/// The file stays open and its size is tracked with a counter (read once when
/// opened), so a write costs a single syscall. Every `recheckInterval` it also
/// checks the file at `path` is still the one it has open, and reopens if the log
/// was deleted or moved by hand.
///
/// With `redirectStderr`, the file is installed as the process's stderr and
/// stdout, so NSLog, print and crash output land in it too.
final class RotatingLogFile: @unchecked Sendable {
    static let defaultMaxBytes = 1 << 20 // 1MB, same as the backend
    static let defaultKeep = 3
    static let defaultRecheckInterval: TimeInterval = 5
    static let rotationRetryDelay: TimeInterval = 60

    let path: String
    private let maxBytes: Int
    private let keep: Int
    private let redirectStderr: Bool
    private let recheckInterval: TimeInterval
    private let lock = NSLock() // uiLog is called from several threads
    private var fd: Int32 = -1
    // Bytes in the current file, advanced by our writes. Output written to the
    // redirected stderr by other code (NSLog, crashes) isn't counted until reopen.
    private var size = 0
    private var checkedAt = Date.distantPast
    private var rotationPausedUntil = Date.distantPast

    init(path: String, maxBytes: Int = defaultMaxBytes, keep: Int = defaultKeep,
         recheckInterval: TimeInterval = defaultRecheckInterval, redirectStderr: Bool) {
        self.path = path
        self.maxBytes = maxBytes
        self.keep = keep
        self.recheckInterval = recheckInterval
        self.redirectStderr = redirectStderr
        if !openFile() {
            // Couldn't open the log (e.g. data dir missing): keep the existing
            // stderr rather than silently dropping every line.
            fd = STDERR_FILENO
        }
    }

    func write(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if now.timeIntervalSince(checkedAt) >= recheckInterval {
            checkedAt = now
            if !fileStillAtPath() { openFile() } // deleted/moved by hand: start a fresh file
        }
        if size >= maxBytes, now >= rotationPausedUntil {
            rotate(now: now)
        }
        let bytes = Array(text.utf8)
        let written = bytes.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
        if written > 0 { size += written }
    }

    /// Moves the full log aside, opens a fresh one, and only then shifts the backups
    /// — so if the fresh file can't be opened nothing is lost: the log is put back
    /// and rotation is retried later.
    private func rotate(now: Date) {
        let aside = path + ".rotating"
        guard rename(path, aside) == 0 else {
            rotationPausedUntil = now.addingTimeInterval(Self.rotationRetryDelay)
            return
        }
        guard openFile() else {
            rename(aside, path)
            rotationPausedUntil = now.addingTimeInterval(Self.rotationRetryDelay)
            return
        }
        unlink("\(path).\(keep)")
        for i in stride(from: keep - 1, through: 1, by: -1) {
            rename("\(path).\(i)", "\(path).\(i + 1)")
        }
        rename(aside, "\(path).1")
    }

    /// Whether the file at `path` is the one we have open.
    private func fileStillAtPath() -> Bool {
        var atPath = stat(), open = stat()
        guard lstat(path, &atPath) == 0, fstat(fd, &open) == 0 else { return false }
        return atPath.st_dev == open.st_dev && atPath.st_ino == open.st_ino
    }

    @discardableResult
    private func openFile() -> Bool {
        let newFD = Darwin.open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
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
            if fd >= 0 && fd != STDERR_FILENO { close(fd) }
            fd = newFD
        }
        return true
    }
}
