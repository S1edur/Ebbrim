import Foundation

private let now = utc("2026-11-22T21:00:00Z")

private func snap(_ source: UsageSnapshot.Source, ago: TimeInterval, used: Double = 40,
                  resetIn: TimeInterval = 3600, weekly: Double? = 10, plan: String? = nil) -> UsageSnapshot {
    let prefix = source == .codex ? "codex" : "claude"
    return UsageSnapshot(
        session: LimitWindow(id: "\(prefix).session", span: .session, usedPercent: used, resetsAt: now.addingTimeInterval(resetIn)),
        weekly: weekly.map { LimitWindow(id: "\(prefix).weekly", span: .weekly, usedPercent: $0, resetsAt: now.addingTimeInterval(86400)) },
        capturedAt: now.addingTimeInterval(-ago), source: source, plan: plan)
}

private func agg(codex: Bool = true) -> (UsageFeed, UsageAggregator) {
    let feed = UsageFeed()
    return (feed, UsageAggregator(feed: feed, codexEnabled: { codex }))
}

func aggregatorTests() {
    run("testLiveUnderFiveMinutes") {
        let p = UsageAggregator.provider(.claude, latest: snap(.desktopCache, ago: 299), lastProblem: nil, now: now)
        expect(p.freshness == .live && p.name == "Claude" && p.sourceLabel == "Claude Desktop", "live \(p)")
    }
    run("testStaleAtFiveMinutes") {
        let p = UsageAggregator.provider(.claude, latest: snap(.desktopCache, ago: 300), lastProblem: nil, now: now)
        expect(p.freshness == .stale && p.capturedAt == now.addingTimeInterval(-300), "stale")
    }
    run("testPastResetShowsZero") {
        let p = UsageAggregator.provider(.claude, latest: snap(.desktopCache, ago: 10, used: 80, resetIn: -1), lastProblem: nil, now: now)
        expect(p.windows.first == LimitWindow(id: "claude.session", span: .session, usedPercent: 0, resetsAt: nil), "reset \(p.windows)")
        expect(p.windows.last?.usedPercent == 10 && p.windows.count == 2, "weekly untouched")
    }
    run("testNewestSourceWins") {
        let (feed, a) = agg()
        a.receive(.snapshot(snap(.statusLine, ago: 600)), from: .statusLine, now: now)      // 20:50
        a.receive(.snapshot(snap(.desktopCache, ago: 720)), from: .desktopCache, now: now)  // 20:48, older
        let c = feed.providers.first { $0.kind == .claude }
        expect(c?.capturedAt == now.addingTimeInterval(-600) && c?.sourceLabel == "Claude Code CLI", "newest \(String(describing: c))")
    }
    run("testOlderSnapshotIgnored") {
        let (feed, a) = agg()
        a.receive(.snapshot(snap(.desktopCache, ago: 60, used: 50)), from: .desktopCache, now: now)
        a.receive(.snapshot(snap(.desktopCache, ago: 120, used: 20)), from: .desktopCache, now: now)
        expect(feed.providers.first?.headlineUsed == 50, "kept newer")
    }
    run("testFormatChangedKeepsReading") {
        let (feed, a) = agg()
        a.receive(.snapshot(snap(.desktopCache, ago: 60, used: 50)), from: .desktopCache, now: now)
        a.receive(.formatChanged("x"), from: .desktopCache, now: now)
        expect(feed.providers.first?.headlineUsed == 50 && feed.providers.first?.freshness == .live, "kept")
    }
    run("testCodexDisabledIsOmitted") {
        let (feed, a) = agg(codex: false)
        a.receive(.snapshot(snap(.desktopCache, ago: 1)), from: .desktopCache, now: now)
        a.receive(.snapshot(snap(.codex, ago: 1, plan: "Plus")), from: .codex, now: now)
        expect(feed.providers.map(\.kind) == [.claude], "\(feed.providers.map(\.kind))")
    }
    run("testCodexShownAfterClaudeWithPlan") {
        let (feed, a) = agg()
        a.receive(.snapshot(snap(.codex, ago: 1, plan: "Plus")), from: .codex, now: now)
        a.receive(.snapshot(snap(.desktopCache, ago: 1)), from: .desktopCache, now: now)
        expect(feed.providers.map(\.kind) == [.claude, .codex] && feed.providers.last?.plan == "Plus"
               && feed.providers.last?.sourceLabel == "Codex", "order/plan")
    }
    run("testNothingYetOmitsProvider") {
        let (feed, a) = agg()
        a.tick(now: now)
        expect(feed.providers.isEmpty, "no provider before its first result")
    }
    run("testMessages") {
        func f(_ k: ProviderKind, _ r: SourceResult) -> Freshness {
            UsageAggregator.provider(k, latest: nil, lastProblem: r, now: now).freshness
        }
        expect(f(.claude, .noSource) == .needsSetup(hint: "Open Claude Desktop to see usage"), "claude noSource")
        expect(f(.codex, .noSource) == .needsSetup(hint: "Install Codex to see its limits"), "codex noSource")
        expect(f(.codex, .formatChanged("codex:signedOut")) == .needsSetup(hint: "Open Codex and sign in"), "signed out")
        expect(f(.claude, .formatChanged("x")) == .unavailable(reason: "Usage data format changed"), "format")
        expect(UsageAggregator.provider(.claude, latest: nil, lastProblem: .noSource, now: now).windows.isEmpty, "no windows")
    }
    run("testStatusLineNoSourceDoesNotHideDesktopProblem") {
        let (feed, a) = agg()
        a.receive(.formatChanged("x"), from: .desktopCache, now: now)
        a.receive(.noSource, from: .statusLine, now: now)
        expect(feed.providers.first?.freshness == .unavailable(reason: "Usage data format changed"), "\(feed.providers)")
    }
    run("testWakeAfterHours") {
        let p = UsageAggregator.provider(.claude, latest: snap(.desktopCache, ago: 3 * 3600, used: 70, resetIn: -3600),
                                         lastProblem: nil, now: now)
        expect(p.freshness == .stale && p.headlineUsed == 0, "stale + reset")
    }
}
