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

    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "butler.sidecar.write")
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<SidecarResponse, Error>] = [:]
    private var readBuffer = Data()

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
        if let dataDir { env["BUTLER_DATA_DIR"] = dataDir }
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data)
        }
        proc.terminationHandler = { [weak self] _ in
            self?.handleTermination()
        }

        try proc.run()
        lock.lock()
        process = proc
        stdin = inPipe.fileHandleForWriting
        lock.unlock()
    }

    private func handleTermination() {
        // Fail everything in flight so awaiting callers don't hang forever.
        lock.lock()
        let inflight = pending
        pending.removeAll()
        readBuffer.removeAll() // drop any half-received line so it can't corrupt the next frame
        stdin = nil
        process = nil
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, maxRestartDelay)
        lock.unlock()

        for (_, cont) in inflight { cont.resume(throwing: SidecarError.notRunning) }

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            try? self?.start()
        }
    }

    // MARK: - Framing

    private func ingest(_ data: Data) {
        lock.lock()
        readBuffer.append(data)
        var lines: [Data] = []
        while let nl = readBuffer.firstIndex(of: 0x0A) {
            lines.append(readBuffer.subdata(in: readBuffer.startIndex..<nl))
            readBuffer.removeSubrange(readBuffer.startIndex...nl)
        }
        lock.unlock()

        for line in lines { deliver(line) }
    }

    private func deliver(_ line: Data) {
        guard let resp = try? JSONDecoder().decode(SidecarResponse.self, from: line) else { return }
        lock.lock()
        let cont = pending.removeValue(forKey: resp.id)
        // A clean response means the sidecar is healthy again — reset backoff.
        restartDelay = 0.1
        lock.unlock()
        cont?.resume(returning: resp)
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

    private func registerPending(_ id: Int, _ cont: CheckedContinuation<SidecarResponse, Error>) {
        lock.lock(); defer { lock.unlock() }
        pending[id] = cont
    }

    private func send(_ makeRequest: (Int) -> SidecarRequest) async throws -> SidecarResponse {
        let (id, handle) = reserveRequest()
        let request = makeRequest(id)
        let data = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation { cont in
            guard let handle else {
                cont.resume(throwing: SidecarError.notRunning)
                return
            }
            registerPending(id, cont)

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
    }

    // Resolve a pending request with an error if it hasn't already completed.
    // removeValue makes response/timeout/write-error races resolve to one winner.
    private func failPending(_ id: Int, _ error: Error) {
        lock.lock()
        let cont = pending.removeValue(forKey: id)
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

    func list() async throws -> [Note] {
        let resp = try await send { SidecarRequest(id: $0, cmd: "list") }
        if let err = resp.error { throw SidecarError.sidecar(err) }
        return resp.notes ?? []
    }
}
