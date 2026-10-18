import Foundation

// SidecarClient owns the resident butler-core process and speaks the
// newline-delimited JSON protocol over its stdin/stdout. Requests are matched to
// responses by id via continuations. If the process dies it relaunches with a
// small backoff (basic watchdog) and fails any in-flight requests.
// @unchecked Sendable: all shared mutable state is synchronized via `lock`, so
// it's safe to reference across the read/write dispatch queues.
final class SidecarClient: @unchecked Sendable {
    enum SidecarError: Error {
        case notRunning
        case sidecar(String)
        case timeout
    }

    private let requestTimeout: TimeInterval = 5.0

    private let binaryURL: URL
    private let dataDir: String?

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    // Bumped on every launch and termination; output tagged with an older
    // generation (a dead process's pipe still draining) is ignored.
    private var generation = 0

    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "butler.sidecar.write")
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<SidecarResponse, Error>] = [:]
    private var framer = LineFramer()

    // Latency instrumentation: when each in-flight request was written to the pipe.
    private struct InFlight {
        let cmd: String
        let dispatchedAt: UInt64 // DispatchTime nanoseconds
    }
    private var inFlight: [Int: InFlight] = [:]

    // Relaunch backoff state.
    private var restartDelay: TimeInterval = 0.1
    private let maxRestartDelay: TimeInterval = 5.0

    init(binaryURL: URL, dataDir: String? = nil) {
        self.binaryURL = binaryURL
        self.dataDir = dataDir
    }

    // MARK: - Lifecycle

    func start() throws {
        let proc = Process()
        proc.executableURL = binaryURL
        var env = ProcessInfo.processInfo.environment
        env["BUTLER_STDERR_TO_LOG"] = "1"
        if let dataDir { env["BUTLER_DATA_DIR"] = dataDir }
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe

        // The backend owns app.log end to end (rotation included) and, asked via
        // BUTLER_STDERR_TO_LOG, also points its own stderr (panic traces) at it.
        // stdout stays the JSON protocol channel.

        lock.lock()
        generation += 1
        let launchGeneration = generation
        lock.unlock()

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF: the process is gone. Detach, per FileHandle's contract.
                handle.readabilityHandler = nil
                return
            }
            self?.ingest(data, generation: launchGeneration)
        }
        proc.terminationHandler = { [weak self] _ in
            self?.handleTermination()
        }

        try proc.run()
        lock.lock()
        process = proc
        stdin = inPipe.fileHandleForWriting
        stdout = outPipe.fileHandleForReading
        lock.unlock()
    }

    /// Launch the sidecar; if that fails, log it and keep retrying with backoff.
    func startWithRetry() {
        do {
            try start()
        } catch {
            uiLog("sidecar launch failed: \(error); retrying")
            scheduleRestart()
        }
    }

    // Relaunch after the current backoff delay. A failed relaunch (e.g. the binary
    // is missing mid-rebuild) schedules another attempt instead of giving up.
    private func scheduleRestart() {
        lock.lock()
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, maxRestartDelay)
        lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startWithRetry()
        }
    }

    private func handleTermination() {
        // Fail everything in flight so awaiting callers don't hang forever.
        lock.lock()
        let inflight = pending
        pending.removeAll()
        inFlight.removeAll()
        framer.reset()         // drop any half-received line so it can't corrupt the next frame
        generation += 1        // ...and ignore anything the dead pipe still delivers
        stdout?.readabilityHandler = nil
        stdout = nil
        stdin = nil
        process = nil
        lock.unlock()

        for (_, cont) in inflight { cont.resume(throwing: SidecarError.notRunning) }
        scheduleRestart()
    }

    // MARK: - Framing

    private func ingest(_ data: Data, generation dataGeneration: Int) {
        lock.lock()
        guard dataGeneration == generation else {
            lock.unlock()
            return
        }
        let lines = framer.append(data)
        lock.unlock()

        let arrivedAt = DispatchTime.now().uptimeNanoseconds
        for line in lines { deliver(line, arrivedAt: arrivedAt) }
    }

    private func deliver(_ line: Data, arrivedAt: UInt64) {
        guard let resp = try? JSONDecoder().decode(SidecarResponse.self, from: line) else { return }
        let processedAt = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        let cont = pending.removeValue(forKey: resp.id)
        let request = inFlight.removeValue(forKey: resp.id)
        // A clean response means the sidecar is healthy again — reset backoff.
        restartDelay = 0.1
        lock.unlock()
        if let request {
            logLatency(id: resp.id, request: request, resp: resp, bytes: line.count,
                       arrivedAt: arrivedAt, processedAt: processedAt)
        }
        cont?.resume(returning: resp)
    }

    // One line per request in butler-ui.log, e.g.
    //   ⏱ id=7 cmd=fetch notes=200 bytes=81234 roundtrip=3.1ms processing=0.6ms total=3.7ms
    // roundtrip  = dispatch → full reply received (pipe both ways + backend work)
    // processing = reply received → decoded and ready for the UI
    // total      = the two together
    private func logLatency(id: Int, request: InFlight, resp: SidecarResponse, bytes: Int,
                            arrivedAt: UInt64, processedAt: UInt64) {
        func ms(_ from: UInt64, _ to: UInt64) -> String {
            String(format: "%.1fms", Double(to &- from) / 1_000_000)
        }
        let notes = resp.notes.map { " notes=\($0.count)" } ?? ""
        uiLog("⏱ id=\(id) cmd=\(request.cmd)\(notes) bytes=\(bytes)"
              + " roundtrip=\(ms(request.dispatchedAt, arrivedAt))"
              + " processing=\(ms(arrivedAt, processedAt))"
              + " total=\(ms(request.dispatchedAt, processedAt))")
    }

    // MARK: - Requests

    // Locked bookkeeping is kept in synchronous helpers so the lock is never
    // touched directly from the async context (Swift-6-safe).
    private func reserveRequest() -> (id: Int, handle: FileHandle?) {
        lock.lock(); defer { lock.unlock() }
        let id = nextID
        nextID += 1
        return (id, stdin)
    }

    private func registerPending(_ id: Int, cmd: String, _ cont: CheckedContinuation<SidecarResponse, Error>) {
        lock.lock(); defer { lock.unlock() }
        pending[id] = cont
        inFlight[id] = InFlight(cmd: cmd, dispatchedAt: DispatchTime.now().uptimeNanoseconds)
    }

    private func send(_ makeRequest: (Int) -> SidecarRequest) async throws -> SidecarResponse {
        let (id, handle) = reserveRequest()
        let request = makeRequest(id)
        let data = try JSONEncoder().encode(request)

        var detail = ""
        if let k = request.key { detail += " key=\(k)" }
        if let q = request.query { detail += " query=\(q)" }
        if let nid = request.noteID { detail += " note_id=\(nid)" }
        uiLog("-------------") // one separator per request, like app.log
        uiLog("→ req id=\(id) cmd=\(request.cmd)\(detail)")

        do {
            let resp: SidecarResponse = try await withCheckedThrowingContinuation { cont in
                guard let handle else {
                    cont.resume(throwing: SidecarError.notRunning)
                    return
                }
                registerPending(id, cmd: request.cmd, cont)

                // Safety net: never let a caller hang if a response is lost — a crash,
                // a garbled/undecodable frame, or a register/terminate race.
                writeQueue.asyncAfter(deadline: .now() + requestTimeout) { [weak self] in
                    self?.failPending(id, SidecarError.timeout)
                }

                writeQueue.async { [weak self] in
                    do {
                        // Throwing API: writing to a dead pipe fails the request
                        // instead of raising an uncatchable ObjC exception.
                        try handle.write(contentsOf: data)
                        try handle.write(contentsOf: Data([0x0A]))
                    } catch {
                        self?.failPending(id, SidecarError.notRunning)
                    }
                }
            }
            var respDetail = ""
            if let e = resp.error { respDetail += " error=\(e)" }
            if let n = resp.notes { respDetail += " notes=\(n.count)" }
            uiLog("← resp id=\(id) ok=\(resp.ok)\(respDetail)")
            return resp
        } catch {
            uiLog("✗ req id=\(id) cmd=\(request.cmd) failed: \(error)")
            throw error
        }
    }

    // Resolve a pending request with an error if it hasn't already completed.
    // removeValue makes response/timeout/write-error races resolve to one winner.
    private func failPending(_ id: Int, _ error: Error) {
        lock.lock()
        let cont = pending.removeValue(forKey: id)
        inFlight.removeValue(forKey: id)
        lock.unlock()
        cont?.resume(throwing: error)
    }

    func ping() async throws -> Bool {
        try await send { SidecarRequest(id: $0, cmd: "ping") }.ok
    }

    func fetch(_ query: String) async throws -> [Note] {
        let resp = try await send { SidecarRequest(id: $0, cmd: "fetch", query: query) }
        if let err = resp.error { throw SidecarError.sidecar(err) }
        return resp.notes ?? []
    }

    func put(key: String, value: String) async throws {
        let resp = try await send { SidecarRequest(id: $0, cmd: "put", key: key, value: value) }
        if let err = resp.error { throw SidecarError.sidecar(err) }
    }

    func delete(id: Int) async throws {
        let resp = try await send { SidecarRequest(id: $0, cmd: "delete", noteID: id) }
        if let err = resp.error { throw SidecarError.sidecar(err) }
    }

    func list() async throws -> [Note] {
        let resp = try await send { SidecarRequest(id: $0, cmd: "list") }
        if let err = resp.error { throw SidecarError.sidecar(err) }
        return resp.notes ?? []
    }
}
