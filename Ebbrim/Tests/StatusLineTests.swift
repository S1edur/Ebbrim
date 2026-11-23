import Foundation

private func tmp(_ name: String) -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("cn-sl-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d.appendingPathComponent(name)
}

private func object(_ url: URL) -> NSDictionary? {
    (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? NSDictionary }
}

private let script = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/../Resources/statusline.sh")

func statusLineTests() {
    run("testParseStatusLineFile") {
        let d = Data(#"{"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1763781300},"seven_day":{"used_percentage":7,"resets_at":1764353700}},"captured_at":1763770000}"#.utf8)
        let s = StatusLineFile.parse(d)
        expect(s?.session == LimitWindow(id: "claude.session", span: .session, usedPercent: 42.5,
                                          resetsAt: Date(timeIntervalSince1970: 1763781300)), "session")
        expect(s?.weekly?.usedPercent == 7 && s?.capturedAt == Date(timeIntervalSince1970: 1763770000)
               && s?.source == .statusLine, "meta")
        expect(StatusLineFile.parse(Data(#"{"rate_limits":{},"captured_at":1}"#.utf8)) == nil, "empty limits")
    }
    run("testInstallKeepsOtherKeysAndChainsPrevious") {
        let settings = tmp("settings.json"), backup = tmp("prev.json")
        try Data(#"{"model":"opus","statusLine":{"type":"command","command":"echo 'hi'"},"env":{"A":"1"}}"#.utf8).write(to: settings)
        try StatusLineInstaller.install(settings: settings, backup: backup, scriptSource: "/bin/echo")
        let o = object(settings)
        expect(o?["model"] as? String == "opus" && (o?["env"] as? NSDictionary)?["A"] as? String == "1", "other keys kept")
        let cmd = (o?["statusLine"] as? NSDictionary)?["command"] as? String
        let copy = backup.deletingLastPathComponent().appendingPathComponent("statusline.sh").path
        expect(cmd == #"EBBRIM_STATUSLINE=1 EBBRIM_PREV_STATUSLINE='echo '\''hi'\''' "# + "'\(copy)'", "command: \(cmd ?? "nil")")
        expect(StatusLineInstaller.isInstalled(settings: settings), "installed")
    }
    run("testUninstallRestoresExactly") {
        let settings = tmp("settings.json"), backup = tmp("prev.json")
        let original = #"{"model":"opus","statusLine":{"type":"command","command":"ccline","padding":0}}"#
        try Data(original.utf8).write(to: settings)
        try StatusLineInstaller.install(settings: settings, backup: backup, scriptSource: "/bin/echo")
        try StatusLineInstaller.uninstall(settings: settings, backup: backup)
        expect(object(settings) == (try JSONSerialization.jsonObject(with: Data(original.utf8)) as! NSDictionary), "round trip")
        expect(!StatusLineInstaller.isInstalled(settings: settings), "uninstalled")
    }
    run("testInstallWithNoSettingsFile") {
        let settings = tmp("settings.json"), backup = tmp("prev.json")
        try StatusLineInstaller.install(settings: settings, backup: backup, scriptSource: "/bin/echo")
        let copy = backup.deletingLastPathComponent().appendingPathComponent("statusline.sh").path
        expect(((object(settings)?["statusLine"] as? NSDictionary)?["command"] as? String) == "EBBRIM_STATUSLINE=1 '\(copy)'", "plain command")
        try StatusLineInstaller.uninstall(settings: settings, backup: backup)
        expect(object(settings)?["statusLine"] == nil, "removed again")
    }
    run("testScriptChainsPrevious") {
        let dir = tmp("out").deletingLastPathComponent()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        p.environment = ["HOME": NSHomeDirectory(), "EBBRIM_DIR": dir.path,
                         "EBBRIM_PREV_STATUSLINE": "cat >/dev/null; echo PREV"]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data(#"{"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1763781300}}}"#.utf8))
        try inPipe.fileHandleForWriting.close()
        p.waitUntilExit()
        let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "PREV", "chained output: \(out)")
        let saved = (try? Data(contentsOf: dir.appendingPathComponent("statusline-usage.json"))).flatMap(StatusLineFile.parse)
        expect(saved?.session?.usedPercent == 5, "file written")
    }
}
