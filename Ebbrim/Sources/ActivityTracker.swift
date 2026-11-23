import Foundation
import Combine

/// Watches the feed for two things:
/// - session usage over time (samples), for the current pace;
/// - the session getting into trouble, to raise the notch island.
///
/// The island is an alert, not an activity meter. Per provider and per
/// session window (one `resetsAt`) it shows at most twice:
/// 1. once when the current pace runs the session out before it resets (risk, yellow);
/// 2. once more, in red, when it's critical: 10% or less left, or out within 30 min.
/// If the first sighting is already critical, only the red one shows. A new
/// window starts over. What was shown is remembered across launches.
final class ActivityTracker: ObservableObject {
    struct Activity: Equatable {
        enum Severity: Equatable { case risk, critical }
        var kind: ProviderKind
        var severity: Severity
        var left: Double                 // % of the window left
        var runsOutAt: Date?             // when the pace empties it, if before the reset
        var resetsAt: Date?
        var span: LimitWindow.Span = .session   // weekly for plans without a 5-hour session (Max 20x)
    }

    /// The island to show right now, if any (one provider at a time).
    @Published private(set) var current: Activity?

    /// One reading of a provider's session usage.
    struct Sample: Equatable { var at: Date; var used: Double }
    /// Session usage over the last hour, per provider (for the pace).
    @Published private(set) var samples: [ProviderKind: [Sample]] = [:]

    // Tunables
    private let history: TimeInterval = 60 * 60       // keep one hour of samples
    private let showFor: TimeInterval = 12            // how long the island stays out
    private let criticalLeft: Double = 10             // % left
    private let criticalSoon: TimeInterval = 30 * 60  // runs out within (session)
    private let criticalSoonWeek: TimeInterval = 24 * 3600  // … (weekly-only plans)

    /// Per provider: which session window, and how far its alerts went
    /// (0 none, 1 risk shown, 2 critical shown).
    private var stage: [ProviderKind: (window: Int, shown: Int)] = [:]
    private var latest: [ProviderUsage] = []
    private var bag: AnyCancellable?
    private var timer: Timer?
    private var hideWork: DispatchWorkItem?

    init(feed: UsageFeed) {
        stage = Self.loadStage()
        bag = feed.$providers.sink { [weak self] in self?.ingest($0) }
        // Re-check on a clock too: the pace changes as time passes.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluate(now: Date())
        }
    }

    private func ingest(_ providers: [ProviderUsage]) {
        latest = providers
        let now = Date()
        for p in providers {
            guard p.freshness == .live || p.freshness == .stale,
                  let session = p.windows.first(where: { $0.span == .session }) else {
                samples[p.kind] = nil; continue
            }
            if p.freshness == .stale { continue }   // old numbers: keep history, add nothing
            let at = p.capturedAt ?? now
            var list = samples[p.kind] ?? []
            if let last = list.last {
                if session.usedPercent < last.used - 0.5 {
                    list = []                       // window reset: start over
                } else if at <= last.at {
                    continue                        // same reading again
                }
            }
            list.append(Sample(at: at, used: session.usedPercent))
            list.removeAll { now.timeIntervalSince($0.at) > history }
            samples[p.kind] = list
        }
        evaluate(now: now)
    }

    private func evaluate(now: Date) {
        for p in latest where p.freshness == .live {
            // The window that limits the plan: the 5-hour session, or the
            // week when the plan has no session (Max 20x).
            guard let s = p.windows.first(where: { $0.span == .session }) ?? p.windows.first(where: { $0.span == .weekly }),
                  let r = s.resetsAt else { continue }
            let weekly = s.span == .weekly
            // Readings of the same window may differ by seconds: bucket to 10 min.
            let window = Int((r.timeIntervalSince1970 / 600).rounded())
            var st = stage[p.kind] ?? (window, 0)
            if st.window != window { st = (window, 0) }

            let pace = SessionPace(s, now: now, recent: weekly ? nil : recentPace(p.kind, now: now))
            let soon = pace.runsOutAt.map { $0.timeIntervalSince(now) <= (weekly ? criticalSoonWeek : criticalSoon) } ?? false
            let critical = pace.left <= criticalLeft || soon
            let risk = pace.runsOutAt != nil

            var show: Activity.Severity?
            if critical, st.shown < 2 { show = .critical }
            else if risk, st.shown < 1 { show = .risk }
            // One island at a time: another provider's alert keeps the screen
            // (a critical one always takes it). Unshown alerts wait, not lost.
            if let show, current == nil || current?.kind == p.kind || show == .critical {
                st.shown = show == .critical ? 2 : 1
                present(Activity(kind: p.kind, severity: show, left: pace.left,
                                 runsOutAt: pace.runsOutAt, resetsAt: r, span: s.span))
            }
            if st != (stage[p.kind] ?? (-1, -1)) { stage[p.kind] = st; saveStage() }
        }
    }

    private func present(_ a: Activity) {
        current = a
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.current = nil }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + showFor, execute: w)
    }

    // MARK: memory across launches

    private static let key = "notch.islandStage"
    private static func loadStage() -> [ProviderKind: (window: Int, shown: Int)] {
        guard let d = UserDefaults.standard.dictionary(forKey: key) as? [String: [Int]] else { return [:] }
        var out: [ProviderKind: (window: Int, shown: Int)] = [:]
        for (k, v) in d where v.count == 2 { if let kind = ProviderKind(rawValue: k) { out[kind] = (v[0], v[1]) } }
        return out
    }
    private func saveStage() {
        guard !UsageFeed.isMock else { return }   // mock data: don't remember fake alerts
        var d: [String: [Int]] = [:]
        for (k, v) in stage { d[k.rawValue] = [v.window, v.shown] }
        UserDefaults.standard.set(d, forKey: Self.key)
    }
}

extension ActivityTracker {
    /// How long we've been sampling this provider's session (oldest → now).
    func sampledFor(_ kind: ProviderKind, now: Date = Date()) -> TimeInterval? {
        samples[kind]?.first.map { now.timeIntervalSince($0.at) }
    }

    /// Session pace over the last `lookback` of readings, when they cover at
    /// least `minSpan` (else nil: not enough to tell yet).
    func recentPace(_ kind: ProviderKind, now: Date = Date(),
                    lookback: TimeInterval = 30 * 60, minSpan: TimeInterval = 10 * 60) -> RecentPace? {
        guard let list = samples[kind], let last = list.last else { return nil }
        let from = now.addingTimeInterval(-lookback)
        // The newest sample at or before the lookback start, else the oldest in it.
        let ref = list.last(where: { $0.at <= from }) ?? list.first!
        let span = now.timeIntervalSince(ref.at)
        guard span >= minSpan else { return nil }
        let rate = max(0, last.used - ref.used) / (span / 3600)
        return RecentPace(perHour: rate, minutes: Int(min(span, lookback) / 60))
    }
}

extension ActivityTracker.Activity {
    /// The island's headline: "Runs out in ~1h 50m" / "8% left · out in ~12m".
    var headline: String {
        let out = runsOutAt.map { Self.long(max(0, $0.timeIntervalSinceNow)) }
        switch severity {
        case .risk:
            return out.map { "Runs out in ~\($0)" } ?? "\(Theme.pct(left)) left"
        case .critical:
            if left <= 0 { return span == .weekly ? "Week used up" : "Session used up" }
            return out.map { "\(Theme.pct(left)) left · out in ~\($0)" } ?? "Only \(Theme.pct(left)) left"
        }
    }

    /// "Resets in 2h 14m" / "Resets in 2d 4h" (relative to `now`)
    func resetText(now: Date = Date()) -> String {
        guard let r = resetsAt else { return "Session active" }
        return "Resets in \(Self.long(max(0, r.timeIntervalSince(now))))"
    }

    /// compact(), with days past a day: "1d 23h".
    static func long(_ t: TimeInterval) -> String {
        guard t >= 24 * 3600 else { return compact(t, floor: 60) }
        let d = Int(t) / 86400, h = (Int(t) % 86400) / 3600
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }

    /// 45s→"1m", 50m→"50m", 1h05→"1h", 2h15→"2h 15m"
    static func compact(_ t: TimeInterval, floor: TimeInterval) -> String {
        let s = max(t, floor)
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        if h == 0 { return "\(max(1, m))m" }
        return m < 5 ? "\(h)h" : "\(h)h \(m)m"
    }
}
