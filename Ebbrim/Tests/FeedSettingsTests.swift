import Foundation

func feedSettingsTests() {
    run("testPerformForwardsAction") {
        let feed = UsageFeed()
        var got: [FeedAction] = []
        feed.onAction = { got.append($0) }
        feed.perform(.setCodex(false))
        feed.perform(.setTerminal(true))
        expect(got == [.setCodex(false), .setTerminal(true)], "\(got)")
        expect(feed.settings == FeedSettings(codexEnabled: true, terminalConnected: false, launchAtLogin: false), "defaults")
    }
    run("testMockFeedAppliesActions") {
        let feed = UsageFeed.mock()
        feed.perform(.setLaunchAtLogin(true))
        feed.perform(.setCodex(false))
        expect(feed.settings.launchAtLogin && !feed.settings.codexEnabled, "\(feed.settings)")
    }
}

func feedSettingsTests2() {
    run("testMockAppliesClaudeAndServers") {
        let feed = UsageFeed.mock()
        expect(feed.settings.claudeEnabled && feed.settings.serversEnabled, "defaults on")
        feed.perform(.setClaude(false)); feed.perform(.setServers(false))
        expect(!feed.settings.claudeEnabled && !feed.settings.serversEnabled, "\(feed.settings)")
    }
    run("testClaudeDisabledIsOmitted") {
        let feed = UsageFeed()
        let a = UsageAggregator(feed: feed, codexEnabled: { true }, claudeEnabled: { false })
        let now = Date()
        a.receive(.snapshot(UsageSnapshot(session: nil, weekly: LimitWindow(id: "claude.weekly", span: .weekly, usedPercent: 1, resetsAt: nil),
                                          capturedAt: now, source: .desktopCache)), from: .desktopCache, now: now)
        a.receive(.snapshot(UsageSnapshot(session: nil, weekly: LimitWindow(id: "codex.weekly", span: .weekly, usedPercent: 1, resetsAt: nil),
                                          capturedAt: now, source: .codex)), from: .codex, now: now)
        expect(feed.providers.map(\.kind) == [.codex], "\(feed.providers.map(\.kind))")
    }
}
