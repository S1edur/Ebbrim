import Foundation

func firstRunTests() {
    run("testFreshInstallHasNothingConnected") {
        let d = UserDefaults(suiteName: "eb.test.\(UUID())")!
        for key in ["claudeEnabled", "codexEnabled", "serversEnabled"] {
            expect(SourceSwitches.isOn(key, in: d) == false, "\(key) off on a fresh install")
        }
    }
    run("testSwitchRemembersConnect") {
        let d = UserDefaults(suiteName: "eb.test.\(UUID())")!
        d.set(true, forKey: "codexEnabled")
        expect(SourceSwitches.isOn("codexEnabled", in: d), "on after Connect")
    }
}

func mockFreshTests() {
    run("testMockFreshShowsNothingUntilConnect") {
        let feed = UsageFeed.mock(fresh: true)
        expect(feed.providers.isEmpty && !feed.settings.claudeEnabled && !feed.settings.codexEnabled
               && !feed.settings.serversEnabled, "fresh: \(feed.providers.map(\.kind)) \(feed.settings)")
        feed.perform(.setCodex(true))
        expect(feed.providers.map(\.kind) == [.codex], "codex appears after Connect: \(feed.providers.map(\.kind))")
    }
}
