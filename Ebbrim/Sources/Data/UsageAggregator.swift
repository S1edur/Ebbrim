import Foundation

/// Keeps the newest reading per provider, decides how fresh it is, and writes
/// `UsageFeed.providers` — the only thing the UI reads. Main thread only.
final class UsageAggregator {
    static let liveFor: TimeInterval = 300

    private let feed: UsageFeed
    private let codexEnabled: () -> Bool
    private let claudeEnabled: () -> Bool
    private var latest: [ProviderKind: UsageSnapshot] = [:]
    private var problem: [ProviderKind: SourceResult] = [:]
    private var timer: Timer?

    init(feed: UsageFeed, codexEnabled: @escaping () -> Bool, claudeEnabled: @escaping () -> Bool = { true }) {
        self.feed = feed
        self.codexEnabled = codexEnabled
        self.claudeEnabled = claudeEnabled
    }

    /// Re-evaluates every 30 s, so ages, staleness and resets move on their own.
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    func receive(_ r: SourceResult, from source: UsageSnapshot.Source, now: Date = Date()) {
        let kind: ProviderKind = source == .codex ? .codex : .claude
        switch r {
        case .snapshot(let s):
            if let kept = latest[kind], kept.capturedAt >= s.capturedAt { break }
            latest[kind] = s
            problem[kind] = nil
        case .noSource where source == .statusLine:
            break                                   // optional source, not connected
        case .noSource, .formatChanged:
            problem[kind] = r
        }
        tick(now: now)
    }

    /// Drops everything known about a provider (its source was disconnected).
    func forget(_ kind: ProviderKind, now: Date = Date()) {
        latest[kind] = nil
        problem[kind] = nil
        tick(now: now)
    }

    /// Drops the reading only if it came from `source` (e.g. the terminal was
    /// disconnected but Claude Desktop still feeds Claude).
    func forget(source: UsageSnapshot.Source, now: Date = Date()) {
        let kind: ProviderKind = source == .codex ? .codex : .claude
        if latest[kind]?.source == source { latest[kind] = nil }
        tick(now: now)
    }

    func tick(now: Date = Date()) {
        var kinds: [ProviderKind] = []
        if claudeEnabled() { kinds.append(.claude) }
        if codexEnabled() { kinds.append(.codex) }
        let providers = kinds.compactMap { kind -> ProviderUsage? in
            guard latest[kind] != nil || problem[kind] != nil else { return nil }   // nothing heard yet
            return Self.provider(kind, latest: latest[kind], lastProblem: problem[kind], now: now)
        }
        if providers != feed.providers { feed.providers = providers }
    }

    static func provider(_ kind: ProviderKind, latest: UsageSnapshot?, lastProblem: SourceResult?,
                         now: Date) -> ProviderUsage {
        let name = kind == .claude ? "Claude" : "Codex"
        guard let s = latest else {
            return ProviderUsage(kind: kind, name: name, windows: [], capturedAt: nil,
                                 freshness: setupState(kind, lastProblem), sourceLabel: name)
        }
        let windows = [s.session, s.weekly].compactMap { $0 }.map { w -> LimitWindow in
            guard let r = w.resetsAt, r < now else { return w }
            return LimitWindow(id: w.id, span: w.span, usedPercent: 0, resetsAt: nil)
        }
        let label: String
        switch s.source {
        case .desktopCache: label = "Claude Desktop"
        case .statusLine: label = "Claude Code CLI"
        case .codex: label = "Codex"
        }
        let fresh: Freshness = now.timeIntervalSince(s.capturedAt) < liveFor ? .live : .stale
        return ProviderUsage(kind: kind, name: name, windows: windows, capturedAt: s.capturedAt,
                             freshness: fresh, sourceLabel: label, plan: s.plan)
    }

    private static func setupState(_ kind: ProviderKind, _ problem: SourceResult?) -> Freshness {
        if case .formatChanged(let why) = problem {
            return why == "codex:signedOut" ? .needsSetup(hint: "Open Codex and sign in")
                                            : .unavailable(reason: "Usage data format changed")
        }
        return kind == .claude ? .needsSetup(hint: "Open Claude Desktop to see usage")
                               : .needsSetup(hint: "Install Codex to see its limits")
    }
}
