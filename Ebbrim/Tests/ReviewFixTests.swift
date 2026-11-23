import Foundation

private let fake = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Fixtures/fake-codex.sh")

private func tmpDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("cn-fix-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func settingsObject(_ url: URL) -> NSDictionary? {
    (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? NSDictionary }
}

func reviewFixTests() {
    // #1
    run("testInstallRefusesInvalidSettings") {
        // Foundation tolerates a trailing comma (keys survive), so test what it can't read.
        for broken in [#"{"model":"opus", "permissions":{"allow":["Bash"]"#, #"["not", "an", "object"]"#] {
            let d = tmpDir(), settings = d.appendingPathComponent("settings.json")
            try Data(broken.utf8).write(to: settings)
            var threw = false
            do { try StatusLineInstaller.install(settings: settings, backup: d.appendingPathComponent("prev.json"),
                                                 scriptSource: "/bin/echo") } catch { threw = true }
            expect(threw, "must throw on \(broken)")
            expect((try? String(contentsOf: settings, encoding: .utf8)) == broken, "file untouched")
        }
    }
    // #3
    run("testUsersOwnStatuslineShIsNotOurs") {
        let d = tmpDir(), settings = d.appendingPathComponent("settings.json")
        try Data(#"{"statusLine":{"type":"command","command":"'/Users/me/bin/statusline.sh'"}}"#.utf8).write(to: settings)
        expect(!StatusLineInstaller.isInstalled(settings: settings), "user's own statusline.sh is not Ebbrim's")
    }
    run("testUninstallWithoutBackupRestoresPrevious") {
        let d = tmpDir(), settings = d.appendingPathComponent("settings.json"), backup = d.appendingPathComponent("prev.json")
        try Data(#"{"statusLine":{"type":"command","command":"echo 'it''s'"}}"#.utf8).write(to: settings)
        try StatusLineInstaller.install(settings: settings, backup: backup, scriptSource: "/bin/echo")
        try FileManager.default.removeItem(at: backup)
        try StatusLineInstaller.uninstall(settings: settings, backup: backup)
        let cmd = (settingsObject(settings)?["statusLine"] as? NSDictionary)?["command"] as? String
        expect(cmd == "echo 'it''s'", "previous command restored: \(cmd ?? "nil")")
    }
    // #4
    run("testInstallKeepsSymlinkAndPermissions") {
        let d = tmpDir(), real = d.appendingPathComponent("dotfiles-settings.json"), link = d.appendingPathComponent("settings.json")
        try Data(#"{"model":"opus"}"#.utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try StatusLineInstaller.install(settings: link, backup: d.appendingPathComponent("prev.json"), scriptSource: "/bin/echo")
        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink, "still a symlink")
        expect(settingsObject(real)?["statusLine"] != nil, "target updated")
        let perms = (try FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? NSNumber)?.intValue
        expect(perms == 0o600, "permissions kept: \(String(describing: perms))")
    }
    // #6
    run("testInstallCopiesScriptOutOfBundle") {
        let d = tmpDir(), settings = d.appendingPathComponent("settings.json"), backup = d.appendingPathComponent("prev.json")
        let src = d.appendingPathComponent("bundle-statusline.sh")
        try Data("#!/bin/bash\necho hi\n".utf8).write(to: src)
        try StatusLineInstaller.install(settings: settings, backup: backup, scriptSource: src.path)
        let copy = d.appendingPathComponent("statusline.sh")
        let cmd = (settingsObject(settings)?["statusLine"] as? NSDictionary)?["command"] as? String ?? ""
        expect(FileManager.default.isExecutableFile(atPath: copy.path), "copied and executable")
        expect(cmd.hasPrefix("EBBRIM_STATUSLINE=1 ") && cmd.hasSuffix("'\(copy.path)'"), "points at copy: \(cmd)")
    }
    // #2
    run("testNoRescanStormWhileNoEntryKnown") {
        let d = tmpDir()
        var results: [SourceResult] = []
        let src = DesktopCacheSource(cacheDir: d, retryDelay: 0.1, minRescanInterval: 60) { results.append($0) }
        src.readNow()                                                  // first look: scans, finds nothing
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        try simpleCacheFile(key: "https://claude.ai/api/organizations/0000/usage?via=plan",
                            body: zstdRawFrame(Data(#"{"five_hour":{"utilization":5}}"#.utf8)),
                            headers: "date:Sat, 21 Nov 2026 21:48:23 GMT\0\0").write(to: d.appendingPathComponent("a_0"))
        src.readNow()                                                  // FSEvents-style call within 60 s: no rescan
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        expect(results == [.noSource, .noSource], "no rescan within interval: \(results)")
    }
    // #5
    run("testTimeoutKillsHelperChildren") {
        let childFile = tmpDir().appendingPathComponent("child.pid")
        let helper = CodexHelper(executable: fake, environment: ["FAKE_MODE": "hang", "FAKE_CHILD": childFile.path])
        let t = Date()
        _ = helper.readRateLimits(timeout: 1)
        let child = (try? String(contentsOf: childFile, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        expect(child != nil && kill(child!, 0) != 0, "grandchild gone")
        expect(Date().timeIntervalSince(t) < 3, "returned promptly")
    }
    run("testCancelStopsInFlightCall") {
        let helper = CodexHelper(executable: fake, environment: ["FAKE_MODE": "hang", "FAKE_CHILD": tmpDir().appendingPathComponent("c").path])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { helper.cancel() }
        let t = Date()
        _ = helper.readRateLimits(timeout: 10)
        expect(Date().timeIntervalSince(t) < 2.5, "cancel ended the call")
    }
    // #9
    run("testHelperExitingAfterInitDoesNotCrash") {
        let r = CodexHelper(executable: fake, environment: ["FAKE_MODE": "exitafterinit"]).readRateLimits(timeout: 5)
        if case .failure(.protocolChanged) = r {} else { expect(false, "protocolChanged expected: \(r)") }
    }
    // #10
    run("testNonAuthErrorIsTransient") {
        expect(CodexHelper(executable: fake, environment: ["FAKE_MODE": "neterror"]).readRateLimits(timeout: 5).failure == .transient, "transient")
        if case .failure(.protocolChanged) = CodexHelper(executable: fake, environment: ["FAKE_MODE": "nomethod"]).readRateLimits(timeout: 5) {}
        else { expect(false, "method not found = protocolChanged") }
    }
    // #11
    run("testServerRequestIsNotAReply") {
        let r = CodexHelper(executable: fake, environment: ["FAKE_MODE": "serverrequest"]).readRateLimits(timeout: 5)
        if case .success(let res) = r { expect(CodexRateLimits.parse(res, at: Date())?.session?.usedPercent == 5, "parsed") }
        else { expect(false, "success expected: \(r)") }
    }
}
