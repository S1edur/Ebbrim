import Foundation

/// `statusline-usage.json`, written by `statusline.sh` from Claude Code's
/// statusLine input: `{"rate_limits": {five_hour, seven_day: {used_percentage,
/// resets_at}}, "captured_at": <unix s>}`.
enum StatusLineFile {
    static func parse(_ data: Data) -> UsageSnapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any],
              let at = (root["captured_at"] as? NSNumber)?.doubleValue else { return nil }
        let session = window(limits["five_hour"], id: "claude.session", span: .session)
        let weekly = window(limits["seven_day"], id: "claude.weekly", span: .weekly)
        guard session != nil || weekly != nil else { return nil }
        return UsageSnapshot(session: session, weekly: weekly,
                             capturedAt: Date(timeIntervalSince1970: at), source: .statusLine,
                             plan: ClaudeUsageJSON.inferredPlan(session: session, weekly: weekly))
    }

    private static func window(_ v: Any?, id: String, span: LimitWindow.Span) -> LimitWindow? {
        guard let w = v as? [String: Any], let used = (w["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        return LimitWindow(id: id, span: span, usedPercent: used,
                           resetsAt: (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
    }
}

/// Adds/removes Ebbrim's statusLine in `~/.claude/settings.json`, keeping
/// the user's previous statusLine running (chained) and restoring it exactly.
/// The previous value is backed up in Ebbrim's own folder, next to a copy
/// of `statusline.sh` (so the status line survives moving or deleting the app).
enum StatusLineInstaller {
    static let settingsURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    static let backupURL = StatusLineSource.folder.appendingPathComponent("statusline-previous.json")
    static let marker = "EBBRIM_STATUSLINE=1 "
    private static let prevVar = "EBBRIM_PREV_STATUSLINE="

    enum InstallerError: LocalizedError {
        case invalidSettings
        var errorDescription: String? {
            "~/.claude/settings.json could not be read as JSON, so Ebbrim left it unchanged."
        }
    }

    static func isInstalled(settings: URL = settingsURL) -> Bool {
        command(in: (try? readSettings(settings)) ?? [:])?.hasPrefix(marker) ?? false
    }

    static func install(settings: URL = settingsURL, backup: URL = backupURL, scriptSource: String) throws {
        var root = try readSettings(settings)
        guard !(command(in: root)?.hasPrefix(marker) ?? false) else { return }
        let script = try refreshScript(source: scriptSource, folder: backup.deletingLastPathComponent())
        let previous = root["statusLine"]
        try write(previous.map { ["statusLine": $0] } ?? [:], to: backup)
        var cmd = marker
        if let prevCmd = (previous as? [String: Any])?["command"] as? String { cmd += prevVar + quote(prevCmd) + " " }
        root["statusLine"] = ["type": "command", "command": cmd + quote(script.path)]
        try write(root, to: settings)
    }

    static func uninstall(settings: URL = settingsURL, backup: URL = backupURL) throws {
        var root = try readSettings(settings)
        guard let cmd = command(in: root), cmd.hasPrefix(marker) else { return }
        if let saved = try? readSettings(backup), FileManager.default.fileExists(atPath: backup.path) {
            root["statusLine"] = saved["statusLine"]                 // nil removes the key
        } else if let prev = previousCommand(in: cmd) {
            root["statusLine"] = ["type": "command", "command": prev]
        } else {
            root["statusLine"] = nil
        }
        try write(root, to: settings)
        // Forget everything Ebbrim kept for the terminal source.
        let folder = backup.deletingLastPathComponent()
        for name in [backup.lastPathComponent, "statusline.sh", "statusline-usage.json"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Copies the bundled script into `folder` (executable) and returns the copy.
    @discardableResult
    static func refreshScript(source: String, folder: URL = StatusLineSource.folder) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent("statusline.sh")
        let tmp = folder.appendingPathComponent(".statusline.sh.new")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(atPath: source, toPath: tmp.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        _ = try fm.replaceItemAt(dest, withItemAt: tmp)
        return dest
    }

    private static func command(in root: [String: Any]) -> String? {
        (root["statusLine"] as? [String: Any])?["command"] as? String
    }

    private static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }

    /// Inverse of `quote` for the value after EBBRIM_PREV_STATUSLINE=.
    private static func previousCommand(in cmd: String) -> String? {
        guard let r = cmd.range(of: prevVar) else { return nil }
        var rest = Substring(cmd[r.upperBound...])
        var out = ""
        while rest.first == "'" {
            rest = rest.dropFirst()
            guard let close = rest.firstIndex(of: "'") else { return nil }
            out += rest[..<close]
            rest = rest[rest.index(after: close)...]
            guard rest.hasPrefix(#"\'"#) else { return out }
            out += "'"
            rest = rest.dropFirst(2)
        }
        return out
    }

    /// Missing file → empty settings; unreadable or not a JSON object → throws.
    private static func readSettings(_ url: URL) throws -> [String: Any] {
        let target = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else { return [:] }
        guard let data = try? Data(contentsOf: target),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw InstallerError.invalidSettings
        }
        return obj
    }

    /// Atomic write to the symlink's target, keeping its permissions.
    private static func write(_ obj: [String: Any], to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let perms = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
        let data = try JSONSerialization.data(withJSONObject: obj,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
        if let perms { try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: target.path) }
    }
}

/// Watches `statusline-usage.json` (polling its mtime every 5 s; the file is
/// tiny and local).
final class StatusLineSource {
    static let folder = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Ebbrim")

    private let file: URL
    private let onResult: (SourceResult) -> Void
    private var timer: Timer?
    private var lastMTime: Date?

    init(file: URL = StatusLineSource.folder.appendingPathComponent("statusline-usage.json"),
         onResult: @escaping (SourceResult) -> Void) {
        self.file = file
        self.onResult = onResult
    }

    func start() {
        guard timer == nil else { return }            // already running
        readNow()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.readIfChanged() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func readNow() { lastMTime = nil; readIfChanged() }

    private func readIfChanged() {
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let mtime else { onResult(.noSource); return }
        guard mtime != lastMTime else { return }
        lastMTime = mtime
        if let s = (try? Data(contentsOf: file)).flatMap(StatusLineFile.parse) { onResult(.snapshot(s)) }
        else { onResult(.formatChanged("statusline file unreadable")) }
    }
}
