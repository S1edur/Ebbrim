import Foundation

func uninstallerTests() {
    func sandbox() -> (root: URL, settings: URL, support: URL, source: URL) {
        let r = FileManager.default.temporaryDirectory.appendingPathComponent("eb-un-\(UUID().uuidString)")
        let support = r.appendingPathComponent("Application Support/Ebbrim")
        let source = r.appendingPathComponent(".ebbrim")
        try! FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        return (r, r.appendingPathComponent("settings.json"), support, source)
    }
    run("testUninstallRestoresStatusLineAndRemovesOurFiles") {
        let s = sandbox()
        let original = #"{"model":"opus","statusLine":{"type":"command","command":"ccline"}}"#
        try Data(original.utf8).write(to: s.settings)
        try StatusLineInstaller.install(settings: s.settings, backup: s.support.appendingPathComponent("statusline-previous.json"),
                                        scriptSource: "/bin/echo")
        var loginItemRemoved = false
        let report = Uninstaller.cleanup(settings: s.settings, support: s.support, sourceCheckout: s.source,
                                         defaultsDomain: "eb.test.\(UUID())", unregisterLoginItem: { loginItemRemoved = true; return true })
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: s.settings)) as! NSDictionary
        expect(restored == (try JSONSerialization.jsonObject(with: Data(original.utf8)) as! NSDictionary), "settings restored")
        expect(!FileManager.default.fileExists(atPath: s.support.path), "support folder gone")
        expect(!FileManager.default.fileExists(atPath: s.source.path), "source checkout gone")
        expect(loginItemRemoved, "login item unregistered")
        expect(report.problems.isEmpty, "no problems: \(report.problems)")
        expect(report.done.contains("Removed the login item"), "reported")
    }
    run("testUninstallLeavesSettingsAloneWhenTerminalNotConnected") {
        let s = sandbox()
        let original = #"{"model":"opus"}"#
        try Data(original.utf8).write(to: s.settings)
        _ = Uninstaller.cleanup(settings: s.settings, support: s.support, sourceCheckout: s.source,
                                defaultsDomain: "eb.test.\(UUID())", unregisterLoginItem: { false })
        expect((try? String(contentsOf: s.settings, encoding: .utf8)) == original, "settings byte-identical")
        let r2 = Uninstaller.cleanup(settings: s.settings, support: s.support, sourceCheckout: s.source,
                                     defaultsDomain: "eb.test.\(UUID())", unregisterLoginItem: { false })
        expect(!r2.done.contains("Removed the login item"), "no login item claimed when there was none")
    }
    run("testUninstallReportsLoginItemFailureButContinues") {
        let s = sandbox()
        struct Boom: Error {}
        let report = Uninstaller.cleanup(settings: s.settings, support: s.support, sourceCheckout: s.source,
                                         defaultsDomain: "eb.test.\(UUID())", unregisterLoginItem: { throw Boom() })
        expect(report.problems.count == 1 && !FileManager.default.fileExists(atPath: s.support.path), "\(report.problems)")
    }
    run("testUninstallClearsDefaults") {
        let domain = "eb.test.\(UUID())"
        UserDefaults.standard.setPersistentDomain(["onboarded": true], forName: domain)
        let s = sandbox()
        _ = Uninstaller.cleanup(settings: s.settings, support: s.support, sourceCheckout: s.source,
                                defaultsDomain: domain, unregisterLoginItem: { false })
        expect(UserDefaults.standard.persistentDomain(forName: domain) == nil, "defaults cleared")
    }
}

func uninstallerPrefsFileTests() {
    run("testUninstallRemovesPreferencesFile") {
        let r = FileManager.default.temporaryDirectory.appendingPathComponent("eb-pf-\(UUID().uuidString)")
        let prefs = r.appendingPathComponent("Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        let domain = "eb.test.\(UUID())"
        try Data("{}".utf8).write(to: prefs.appendingPathComponent("\(domain).plist"))
        _ = Uninstaller.cleanup(settings: r.appendingPathComponent("settings.json"), support: r.appendingPathComponent("s"),
                                sourceCheckout: r.appendingPathComponent("src"), defaultsDomain: domain,
                                preferencesDir: prefs, unregisterLoginItem: { false })
        expect(!FileManager.default.fileExists(atPath: prefs.appendingPathComponent("\(domain).plist").path), "plist file removed")
    }
}
