import Foundation

func disconnectTests() {
    let now = utc("2026-11-23T10:00:00Z")
    func snap(_ s: UsageSnapshot.Source, used: Double) -> UsageSnapshot {
        UsageSnapshot(session: LimitWindow(id: "x.session", span: .session, usedPercent: used, resetsAt: nil),
                      weekly: nil, capturedAt: now, source: s)
    }
    run("testForgetDropsProviderReading") {
        let feed = UsageFeed()
        let a = UsageAggregator(feed: feed, codexEnabled: { true })
        a.receive(.snapshot(snap(.codex, used: 40)), from: .codex, now: now)
        a.forget(.codex, now: now)
        expect(feed.providers.isEmpty, "codex forgotten: \(feed.providers)")
        a.receive(.snapshot(snap(.codex, used: 10)), from: .codex, now: now.addingTimeInterval(-600))
        expect(feed.providers.first?.headlineUsed == 10, "an older reading is accepted after forget")
    }
    run("testForgetStatusLineKeepsDesktopReading") {
        let feed = UsageFeed()
        let a = UsageAggregator(feed: feed, codexEnabled: { false })
        a.receive(.snapshot(snap(.statusLine, used: 30)), from: .statusLine, now: now)
        a.forget(source: .statusLine, now: now)
        expect(feed.providers.isEmpty, "statusLine reading dropped")
        a.receive(.snapshot(snap(.desktopCache, used: 20)), from: .desktopCache, now: now)
        a.forget(source: .statusLine, now: now)
        expect(feed.providers.first?.headlineUsed == 20, "desktop reading kept")
    }
    run("testUninstallRemovesAllOurTerminalFiles") {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("cn-dc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let settings = d.appendingPathComponent("settings.json"), backup = d.appendingPathComponent("statusline-previous.json")
        try StatusLineInstaller.install(settings: settings, backup: backup, scriptSource: "/bin/echo")
        try Data("{}".utf8).write(to: d.appendingPathComponent("statusline-usage.json"))
        try StatusLineInstaller.uninstall(settings: settings, backup: backup)
        let left = try FileManager.default.contentsOfDirectory(atPath: d.path).sorted()
        expect(left == ["settings.json"], "only the user's settings remain: \(left)")
    }
}

func disconnectPromptTests() {
    run("testDisconnectPromptOnlyForDisconnect") {
        expect(DisconnectPrompt.text(for: .setCodex(true)) == nil && DisconnectPrompt.text(for: .setServers(false)) == nil, "no prompt")
        let codex = DisconnectPrompt.text(for: .setCodex(false))
        expect(codex?.title == "Disconnect Codex?" && (codex?.body.contains("Your Codex login is not affected") ?? false), "\(String(describing: codex))")
        let claude = DisconnectPrompt.text(for: .setClaude(false))
        expect(claude?.title == "Disconnect Claude?" && (claude?.body.contains("Claude Desktop's cache") ?? false), "claude")
        let term = DisconnectPrompt.text(for: .setTerminal(false))
        expect(term?.title == "Disconnect Claude Code in Terminal?" && (term?.body.contains("previous statusLine") ?? false), "terminal")
    }
}
