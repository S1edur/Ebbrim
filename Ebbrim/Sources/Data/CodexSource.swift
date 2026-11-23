import AppKit

enum CodexCallError: Error, Equatable {
    case notInstalled, timeout, signedOut, protocolChanged(String), launchFailed
    case transient                       // helper answered with a non-auth error (e.g. offline)
}

/// Signals a process and all its descendants (children first). The helper
/// runs its own child process; killing only the direct pid would orphan it.
func killProcessTree(_ pid: pid_t, _ sig: Int32) {
    func descendants(_ p: pid_t) -> [pid_t] {
        var buf = [pid_t](repeating: 0, count: 64)
        let n = proc_listchildpids(p, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
        let kids = n > 0 ? Array(buf.prefix(Int(n))) : []
        return kids.flatMap { descendants($0) + [$0] }
    }
    for p in descendants(pid) { kill(p, sig) }
    kill(pid, sig)
}

/// Codex's own helper (`codex app-server`, bundled in ChatGPT.app), asked for
/// rate limits over JSON-RPC on stdio. The helper uses Codex's login; Ebbrim
/// never reads it. Only these messages are ever sent: `initialize`,
/// `initialized`, `account/rateLimits/read`.
final class CodexHelper {
    let executable: URL
    private let environment: [String: String]
    private(set) var lastPid: pid_t?
    private let lock = NSLock()
    private var running: Process?

    init(executable: URL, environment: [String: String] = [:]) {
        self.executable = executable
        self.environment = environment
    }

    static func locate() -> CodexHelper? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else { return nil }
        let exe = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        return FileManager.default.isExecutableFile(atPath: exe.path) ? CodexHelper(executable: exe) : nil
    }

    /// Blocking; call off the main thread. The child is gone when this returns.
    func readRateLimits(timeout: TimeInterval = 10) -> Result<[String: Any], CodexCallError> {
        let deadline = Date().addingTimeInterval(timeout)
        let p = Process()
        p.executableURL = executable
        p.arguments = ["app-server"]
        p.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice
        // A helper that exits early must not kill us with SIGPIPE on write.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try p.run() } catch { return .failure(.launchFailed) }
        lastPid = p.processIdentifier
        lock.lock(); running = p; lock.unlock()
        let replies = ReplyReader(stdout.fileHandleForReading)
        defer { finish(p, stdin: stdin) }

        func send(_ obj: [String: Any]) {
            guard let d = try? JSONSerialization.data(withJSONObject: obj, options: .withoutEscapingSlashes) else { return }
            try? stdin.fileHandleForWriting.write(contentsOf: d + Data([0x0A]))
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        send(["id": 0, "method": "initialize",
              "params": ["clientInfo": ["name": "ebbrim", "title": "Ebbrim", "version": version]]])
        switch replies.wait(id: 0, until: deadline) {
        case .timedOut: return .failure(.timeout)
        case .closed: return .failure(.protocolChanged("helper exited during initialize"))
        case .reply(let r) where r["error"] != nil: return .failure(.protocolChanged("initialize refused"))
        case .reply: break
        }
        send(["method": "initialized"])
        send(["id": 1, "method": "account/rateLimits/read", "params": ["excludeResetCreditDetails": true]])
        switch replies.wait(id: 1, until: deadline) {
        case .timedOut: return .failure(.timeout)
        case .closed: return .failure(.protocolChanged("helper exited before replying"))
        case .reply(let r):
            if let err = r["error"] as? [String: Any] {
                if (err["code"] as? Int) == -32601 { return .failure(.protocolChanged("rateLimits/read not found")) }
                let msg = (err["message"] as? String ?? "").lowercased()
                let auth = ["not logged in", "log in", "login", "sign in", "unauthorized", "authentication"]
                    .contains { msg.contains($0) }
                return .failure(auth ? .signedOut : .transient)
            }
            guard let result = r["result"] as? [String: Any] else { return .failure(.protocolChanged("no result")) }
            guard result["rateLimits"] is [String: Any] else { return .failure(.signedOut) }
            return .success(result)
        }
    }

    /// Ends an in-flight call now (app quitting / Codex turned off).
    func cancel() {
        lock.lock(); let p = running; lock.unlock()
        if let p, p.isRunning { killProcessTree(p.processIdentifier, SIGKILL) }
    }

    private func finish(_ p: Process, stdin: Pipe) {
        try? stdin.fileHandleForWriting.close()
        let graceEnd = Date().addingTimeInterval(0.5)
        while p.isRunning && Date() < graceEnd { usleep(20_000) }
        if p.isRunning { killProcessTree(p.processIdentifier, SIGTERM) }
        let killAt = Date().addingTimeInterval(0.5)
        while p.isRunning && Date() < killAt { usleep(20_000) }
        if p.isRunning { killProcessTree(p.processIdentifier, SIGKILL) }
        p.waitUntilExit()
        lock.lock(); running = nil; lock.unlock()
    }
}

/// Reads newline-delimited JSON from the helper on its own thread.
private final class ReplyReader {
    enum Outcome { case reply([String: Any]), timedOut, closed }
    private let cond = NSCondition()
    private var byId: [Int: [String: Any]] = [:]
    private var closed = false

    init(_ handle: FileHandle) {
        Thread.detachNewThread { [self] in
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    // Replies carry an id and no method; server-to-client
                    // requests carry both and are not ours to answer.
                    if let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                       obj["method"] == nil, let id = obj["id"] as? Int {
                        cond.lock(); byId[id] = obj; cond.broadcast(); cond.unlock()
                    }
                }
            }
            cond.lock(); closed = true; cond.broadcast(); cond.unlock()
        }
    }

    func wait(id: Int, until deadline: Date) -> Outcome {
        cond.lock(); defer { cond.unlock() }
        while true {
            if let r = byId[id] { return .reply(r) }
            if closed { return .closed }
            if !cond.wait(until: deadline) { return byId[id].map(Outcome.reply) ?? .timedOut }
        }
    }
}

/// Polls Codex every `interval` while the Mac is awake; backs off on failure.
final class CodexSource {
    private let locate: () -> CodexHelper?
    private let interval: TimeInterval
    private let onResult: (SourceResult) -> Void
    private let queue = DispatchQueue(label: "ebbrim.codex", qos: .utility)
    private var next: DispatchWorkItem?
    private var inFlight = false
    private var failureDelay: TimeInterval = 0
    private var running = false
    private var wakeObserver: NSObjectProtocol?
    private let activeLock = NSLock()
    private var active: CodexHelper?

    init(locate: @escaping () -> CodexHelper? = CodexHelper.locate, interval: TimeInterval = 60,
         onResult: @escaping (SourceResult) -> Void) {
        self.locate = locate
        self.interval = interval
        self.onResult = onResult
    }

    func start() {
        guard !running else { return }
        running = true
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.readNow() }
        readNow()
    }

    func stop() {
        running = false
        next?.cancel(); next = nil
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        wakeObserver = nil
        activeLock.lock(); let h = active; activeLock.unlock()
        h?.cancel()
    }

    /// Main thread only.
    func readNow() {
        guard running, !inFlight else { return }
        inFlight = true
        next?.cancel()
        queue.async { [weak self] in
            guard let self else { return }
            let helper = self.locate()
            self.activeLock.lock(); self.active = helper; self.activeLock.unlock()
            let outcome: Result<[String: Any], CodexCallError> =
                helper.map { $0.readRateLimits() } ?? .failure(.notInstalled)
            self.activeLock.lock(); self.active = nil; self.activeLock.unlock()
            let now = Date()
            DispatchQueue.main.async { self.handle(outcome, at: now) }
        }
    }

    private func handle(_ outcome: Result<[String: Any], CodexCallError>, at now: Date) {
        inFlight = false
        guard running else { return }
        var delay = interval
        switch outcome {
        case .success(let result):
            failureDelay = 0
            if let s = CodexRateLimits.parse(result, at: now) { onResult(.snapshot(s)) }
            else { onResult(.formatChanged("codex: unexpected rateLimits shape")) }
        case .failure(.notInstalled):
            failureDelay = 0
            onResult(.noSource)
        case .failure(.signedOut):
            failureDelay = 0
            onResult(.formatChanged("codex:signedOut"))
        case .failure(.protocolChanged(let why)):
            onResult(.formatChanged("codex: \(why)"))
            delay = backoff()
        case .failure(.timeout), .failure(.launchFailed), .failure(.transient):
            delay = backoff()                           // keep the last reading
        }
        let item = DispatchWorkItem { [weak self] in self?.readNow() }
        next = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func backoff() -> TimeInterval {
        failureDelay = failureDelay == 0 ? 120 : min(failureDelay * 2, 600)
        return failureDelay
    }
}
