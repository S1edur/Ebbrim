import Foundation
import Combine
import AppKit

/// One local dev server detected on a listening TCP port.
struct LocalServer: Identifiable, Equatable {
    let pid: Int32
    let port: Int
    let kind: String       // "Vite", "WordPress", "Python", "Node"…
    let project: String    // cwd basename, e.g. "bridge-local"
    let cpu: Double        // % CPU
    let memMB: Int         // resident memory, MB
    var id: String { "\(pid):\(port)" }
    var url: String { "http://localhost:\(port)" }
}

/// Lists local dev servers by scanning listening TCP ports (lsof), enriches each
/// with its process cwd + full command to name the project and guess the stack,
/// and can open or terminate them. Read-only scan; the only mutation is an
/// explicit user-confirmed terminate.
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [LocalServer] = []

    private let pollInterval: TimeInterval = 6
    private var timer: Timer?

    /// Process command names that are apps/daemons, never the user's dev servers.
    private static let deny = [
        "rapportd", "controlce", "control center", "raycast", "figma", "engram",
        "spotify", "dropbox", "identityservices", "sharingd", "remoted", "launchd",
        "cloudd", "apsd", "trustd", "chrome", "google", "slack", "electron",
        "code helper", "ebbrim", "claude", "steam", "zoom", "arc", "safari",
    ]

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Stops scanning (Local servers switched off) and clears the list.
    func stop() {
        timer?.invalidate(); timer = nil
        servers = []
    }

    func refreshNow() { if timer != nil { poll() } }

    // MARK: actions
    func open(_ s: LocalServer) {
        if let u = URL(string: s.url) { NSWorkspace.shared.open(u) }
    }

    /// SIGTERM the process (graceful). Caller confirms first.
    func terminate(_ s: LocalServer) {
        kill(s.pid, SIGTERM)
        // optimistic removal; the next poll reconciles
        servers.removeAll { $0.id == s.id }
    }

    // MARK: scan
    private func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let found = self.scan()
            DispatchQueue.main.async {
                if found != self.servers { self.servers = found }
            }
        }
    }

    private func scan() -> [LocalServer] {
        // 1) listening ports → (pid, command, [ports])
        guard let raw = Self.run("/usr/sbin/lsof",
                                 ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]) else { return [] }
        var byPid: [Int32: (cmd: String, ports: Set<Int>)] = [:]
        var pid: Int32 = 0
        var cmd = ""
        for line in raw.split(separator: "\n") {
            let s = String(line)
            switch s.first {
            case "p": pid = Int32(s.dropFirst()) ?? 0; cmd = ""
            case "c": cmd = String(s.dropFirst())
            case "n":
                let name = s.dropFirst()
                guard let colon = name.lastIndex(of: ":"),
                      let port = Int(name[name.index(after: colon)...]) else { break }
                if pid > 0 { byPid[pid, default: (cmd, [])].cmd = cmd; byPid[pid]!.ports.insert(port) }
            default: break
            }
        }
        // keep only likely dev processes
        let devPids = byPid.filter { !Self.isDenied($0.value.cmd) }
        if devPids.isEmpty { return [] }

        // 2) batch cwd + per-process command / cpu / memory for those pids
        let pidList = devPids.keys.map(String.init).joined(separator: ",")
        let cwds = Self.cwds(pidList)
        let proc = Self.procInfo(pidList)

        var out: [LocalServer] = []
        for (pid, info) in devPids {
            let p = proc[pid]
            let full = p?.cmd ?? info.cmd
            let cwd = cwds[pid] ?? ""
            // skip processes living inside app bundles / Library (not projects)
            if cwd.contains("/Library/") || cwd.contains(".app/") { continue }
            let project = cwd.isEmpty ? info.cmd : (cwd as NSString).lastPathComponent
            let kind = Self.kind(full: full, cmd: info.cmd)
            for port in info.ports {
                out.append(LocalServer(pid: pid, port: port, kind: kind, project: project,
                                       cpu: p?.cpu ?? 0, memMB: p?.rssMB ?? 0))
            }
        }
        return out.sorted { $0.port < $1.port }
    }

    private static func isDenied(_ cmd: String) -> Bool {
        let c = cmd.lowercased()
        return deny.contains { c.contains($0) }
    }

    private static func cwds(_ pidList: String) -> [Int32: String] {
        guard let raw = run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", pidList, "-Fn"]) else { return [:] }
        var map: [Int32: String] = [:]
        var pid: Int32 = 0
        for line in raw.split(separator: "\n") {
            let s = String(line)
            if s.first == "p" { pid = Int32(s.dropFirst()) ?? 0 }
            else if s.first == "n", pid > 0 { map[pid] = String(s.dropFirst()) }
        }
        return map
    }

    /// pid → (full command, %cpu, resident MB). `command=` must stay last since
    /// it contains spaces; the first three tokens are pid, %cpu, rss(KB).
    private static func procInfo(_ pidList: String) -> [Int32: (cmd: String, cpu: Double, rssMB: Int)] {
        guard let raw = run("/bin/ps", ["-o", "pid=,%cpu=,rss=,command=", "-p", pidList]) else { return [:] }
        var map: [Int32: (String, Double, Int)] = [:]
        for line in raw.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            let parts = t.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4, let pid = Int32(parts[0]) else { continue }
            let cpu = Double(parts[1]) ?? 0
            let rssKB = Int(parts[2]) ?? 0
            map[pid] = (String(parts[3]), cpu, rssKB / 1024)
        }
        return map
    }

    /// Guess the stack from the full command line.
    private static func kind(full: String, cmd: String) -> String {
        let f = full.lowercased()
        if f.contains("wp-playground") || f.contains("wp-now") || f.contains("wp-env") { return "WordPress" }
        if f.contains("storybook") { return "Storybook" }
        if f.contains("vite") { return f.contains("preview") ? "Vite ·prev" : "Vite" }
        if f.contains("next") { return "Next.js" }
        if f.contains("webpack") || f.contains("react-scripts") { return "React" }
        if f.contains("nuxt") { return "Nuxt" }
        if f.contains("astro") { return "Astro" }
        if f.contains("http.server") { return "Python ·static" }
        if f.contains("uvicorn") || f.contains("gunicorn") || f.contains("flask")
            || f.contains("manage.py") || f.contains("django") { return "Python" }
        if f.contains("php") && f.contains("-s") { return "PHP" }
        if f.contains("rails") || f.contains("puma") || f.contains("rackup") { return "Rails" }
        let c = cmd.lowercased()
        if c.contains("node") { return "Node" }
        if c.contains("python") { return "Python" }
        if c.contains("php") { return "PHP" }
        if c.contains("ruby") { return "Ruby" }
        return cmd.isEmpty ? "server" : cmd
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
