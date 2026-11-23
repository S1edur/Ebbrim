import SwiftUI

/// Hover card content for ONE provider. Everything is what's LEFT.
///
/// The layout follows the plan's limits (Figma 2190:23975 / 2192:24419):
/// - with a 5-hour session (Pro, Max 5x): the session is the hero, the week
///   sits in a small ring row at the bottom;
/// - weekly only (Max 20x): the week is the hero and there is no bottom row.
/// Hero = meter of what's left + the pace (% per hour) + a forecast of when
/// it runs out, over a tick meter that drains from 100% to 0%.
struct ProviderPanel: View {
    let provider: ProviderUsage
    /// Session pace over the last minutes (from ActivityTracker), if known.
    var recent: RecentPace? = nil
    /// How long the session has been sampled for (to count down to a pace).
    var sampledFor: TimeInterval? = nil
    /// Extra height the card should add at its bottom only (the pace
    /// explainer), so what's under the cursor never moves.
    var onGrow: (CGFloat) -> Void = { _ in }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            content(now: ctx.date)
        }
        .padding(CardMetrics.pad)
        .frame(width: CardMetrics.width, alignment: .leading)
    }

    private var session: LimitWindow? { provider.windows.first { $0.span == .session } }
    private var weekly: LimitWindow? { provider.windows.first { $0.span == .weekly } }
    /// The window the card is about: the session when the plan has one.
    private var hero: LimitWindow? { session ?? weekly }
    private var others: [LimitWindow] {
        provider.windows.filter { if case .other = $0.span { return true }; return false }
    }
    private var isReadable: Bool {
        switch provider.freshness { case .live, .stale: return true; default: return false }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let pace = hero.map { SessionPace($0, now: now, recent: $0.span == .session ? recent : nil,
                                          sampledFor: $0.span == .session ? sampledFor : nil) }
        let week = session != nil ? weekly.map { WeekOutlook($0, now: now) } : nil
        VStack(alignment: .leading, spacing: 14) {
            header(pace: pace, now: now)
            switch provider.freshness {
            case .needsSetup(let hint):
                StateNote(icon: "plus", tint: .white.opacity(0.7), title: "Not connected yet", detail: hint)
            case .unavailable(let reason):
                StateNote(icon: "exclamationmark.triangle.fill", tint: Theme.yellow,
                          title: "Can't read usage", detail: reason)
            case .live, .stale:
                if provider.windows.isEmpty {
                    StateNote(icon: "hourglass", tint: .white.opacity(0.7),
                              title: "No data yet", detail: "Numbers appear after the first reading.")
                } else {
                    if let pace {
                        if pace.left <= 0 { UsedUpSection(pace: pace, now: now) }
                        else { PaceSection(pace: pace, week: week, now: now, onGrow: onGrow) }
                    }
                    if session != nil, let w = weekly { WeeklyRow(window: w) }
                    ForEach(others) { OtherRow(window: $0) }
                }
            }
        }
    }

    private func header(pace: SessionPace?, now: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        ProviderLogo(kind: provider.kind, size: 14, color: ProviderTint.logo(provider.kind))
                        Text(provider.name)
                            .font(CardType.title).tracking(-0.15)
                            .foregroundStyle(.white)
                    }
                    if let plan = provider.plan {
                        let tint = ProviderTint.logo(provider.kind)
                        Text(plan)
                            .font(CardType.tag).tracking(0.2)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6).padding(.vertical, 2.5)
                            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                subtitle(now: now)
                    .font(CardType.caption).tracking(0.05)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 8)
            if let pace, isReadable {
                LeftMeter(left: pace.left, level: pace.level)
            }
        }
    }

    @ViewBuilder private func subtitle(now: Date) -> some View {
        switch provider.freshness {
        case .needsSetup: Text("Not set up")
        case .unavailable: Text("Unavailable")
        case .live, .stale:
            if let h = hero, let r = h.resetsAt {
                let what = h.span == .session ? "Session" : "Weekly session"   // Max 20x: the week is the session
                if h.usedPercent >= 100 {
                    Text("\(what) limit reached").lineLimit(1)
                } else {
                    Text("\(what) resets \(When.phrase(r, now: now))").lineLimit(1)
                }
            } else {
                Text(provider.sourceLabel)
            }
        }
    }
}

extension ProviderUsage {
    /// The window the UI is about: the session when the plan has one.
    var heroWindow: LimitWindow? {
        windows.first { $0.span == .session } ?? windows.first { $0.span == .weekly } ?? windows.first
    }
    /// % left in the hero window, 0…100.
    var leftPercent: Double? { heroWindow.map { min(100, max(0, 100 - $0.usedPercent)) } }
}

/// Shared size of the hover card: every panel has the same width, so moving
/// between them only morphs the height.
enum CardMetrics {
    static let width: CGFloat = 296
    static let pad: CGFloat = 12
    static let radius: CGFloat = 14
    static let gap: CGFloat = 8           // between the pill and the card
}

/// "in 2h 14m" within a day, "on Wed 8:00pm" further out; "at 6:40pm" /
/// "on Mon 5:00pm" for a moment in time.
enum When {
    static func phrase(_ d: Date, now: Date) -> String {
        let t = d.timeIntervalSince(now)
        if t < 24 * 3600 { return "in \(ActivityTracker.Activity.compact(max(0, t), floor: 60))" }
        return "on \(day.string(from: d))"
    }
    static func at(_ d: Date, now: Date) -> String {
        d.timeIntervalSince(now) < 20 * 3600 ? time.string(from: d) : dayHour.string(from: d)
    }
    static let dayHour: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE ha"; f.amSymbol = "am"; f.pmSymbol = "pm"; return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE h:mma"; f.amSymbol = "am"; f.pmSymbol = "pm"; return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mma"; f.amSymbol = "am"; f.pmSymbol = "pm"; return f
    }()
}

/// How fast a window is being used right now and whether what's left lasts.
///
/// Pace = the last ~30 minutes of activity when we have them (so a burst
/// mid-session counts right away), else the average since the window began.
/// Optimal = what's left ÷ time left: the pace that uses exactly the rest by
/// the reset. Faster runs out early, slower leaves some unused.
struct SessionPace: Equatable {
    enum Basis: Equatable { case recent(minutes: Int), sinceStart }

    var span: LimitWindow.Span
    var used: Double
    var left: Double                      // % of the window left
    var perHour: Double?                  // pace, % per hour
    var basis: Basis = .sinceStart
    var resetsAt: Date?
    var timeLeft: TimeInterval = 0
    var runsOutAt: Date?                  // set only when it runs dry before the reset
    var leftAtReset: Double?              // % still left at the reset if the pace holds
    var hours: Double = 5                 // window length
    var elapsed: Double = 0               // 0…1 of the window's time gone
    /// While measuring: when the pace will be known (10 min of data).
    var readyAt: Date?

    /// The pace that uses exactly what's left by the reset.
    var optimal: Double? { timeLeft > 60 ? left / (timeLeft / 3600) : nil }
    /// Pace against the optimal one: 1 = lands exactly on the reset.
    var ratio: Double? {
        guard let r = perHour, let o = optimal else { return nil }
        return o > 0 ? r / o : (r > 0 ? 2 : 1)
    }

    init(_ w: LimitWindow, now: Date, recent: RecentPace? = nil, sampledFor: TimeInterval? = nil) {
        span = w.span
        used = w.usedPercent
        left = max(0, 100 - w.usedPercent)
        resetsAt = w.resetsAt
        guard let r = w.resetsAt, let len = WindowMath.length(w.span) else { return }
        let l = max(0, r.timeIntervalSince(now))
        timeLeft = l
        let gone = len - l
        hours = len / 3600
        elapsed = min(1, max(0, gone / len))
        if let recent {
            perHour = recent.perHour; basis = .recent(minutes: recent.minutes)
        } else if gone >= 10 * 60 {
            perHour = max(0, used) / (gone / 3600); basis = .sinceStart
        }
        guard let rate = perHour else {
            // Whichever reaches 10 minutes first: the window itself or our readings.
            let wait = min(10 * 60 - gone, 10 * 60 - (sampledFor ?? 0))
            readyAt = now.addingTimeInterval(max(0, wait))
            return
        }
        leftAtReset = max(0, left - rate * l / 3600)
        if rate > 0, left > 0 {
            let eta = left / rate * 3600
            if eta < l { runsOutAt = now.addingTimeInterval(eta) }
        }
    }

    var level: UsageLevel {
        if left <= 10 { return .critical }
        if left <= 30 || runsOutAt != nil { return .warning }
        return .normal
    }
}

/// Session pace measured over the last minutes of readings.
struct RecentPace: Equatable {
    var perHour: Double
    var minutes: Int
}

/// Does the week last at the usual pace? The week's own average (which
/// already includes nights and breaks) carried on to the weekly reset.
struct WeekOutlook: Equatable {
    var left: Double
    var resetsAt: Date?
    var leftAtReset: Double?
    var runsOutAt: Date?

    init(_ w: LimitWindow, now: Date) {
        left = max(0, 100 - w.usedPercent)
        resetsAt = w.resetsAt
        guard let r = w.resetsAt else { return }
        let l = max(0, r.timeIntervalSince(now))
        let gone = 7 * 86400 - l
        guard gone >= 3600 else { return }
        let rate = max(0, w.usedPercent) / gone                  // % per second
        leftAtReset = max(0, left - rate * l)
        if rate > 0, left > 0, left / rate < l { runsOutAt = now.addingTimeInterval(left / rate) }
    }
}

/// White → yellow → red: the color story of the meter, its glow and the card.
enum UsageLevel: Equatable {
    case normal, warning, critical
    var color: Color {
        switch self {
        case .normal: return .white
        case .warning: return Theme.yellow
        case .critical: return Theme.red
        }
    }
}

enum ProviderTint {
    static func logo(_ k: ProviderKind) -> Color {
        k == .claude ? Theme.claudeOrange : .white.opacity(0.7)
    }
}

/// What's left, in a small box (Figma "Bar"): a soft gradient fill anchored
/// on the right that drains from 100% to 0%, a white number glowing in the
/// level color.
private struct LeftMeter: View {
    let left: Double
    let level: UsageLevel

    var body: some View {
        let f = CGFloat(min(1, max(0, left / 100)))
        let c = level.color
        Text(Theme.pct(left))
            .font(CardType.value).tracking(-0.4)
            .contentTransition(.numericText(value: left))
            .foregroundStyle(.white)
            .shadow(color: c.opacity(level == .normal ? 0.75 : 1), radius: 9)
            .padding(.horizontal, 9)
            .frame(minWidth: 70, minHeight: 28)
            .background(alignment: .trailing) {
                GeometryReader { g in
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4)
                        .fill(LinearGradient(colors: [c, c.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                        .opacity(level == .normal ? 0.2 : 0.38)
                        .frame(width: g.size.width * f)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .background(Color(white: 0.45).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(.smooth(duration: 0.45), value: left)
            .animation(.smooth(duration: 0.45), value: level)
    }
}

/// "32%/h  Avg. usage ⓘ ··· Runs out in ~1h 50m" over a pace meter whose
/// middle is the optimal pace (uses exactly what's left by the reset).
/// Slower fills to the left and leaves some unused; faster fills to the
/// right and runs out before the reset.
private struct PaceSection: View {
    let pace: SessionPace
    var week: WeekOutlook? = nil
    let now: Date
    var onGrow: (CGFloat) -> Void = { _ in }
    @State private var explain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let r = pace.perHour {
                        Text("\(Pct.rate(r))/h")
                            .font(CardType.value).tracking(-0.4)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: r))
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Avg. usage")
                            Image(systemName: "info.circle")
                                .font(CardType.caption)
                                .opacity(explain ? 1 : 0.8)
                        }
                        .font(CardType.caption).foregroundStyle(.white.opacity(0.75))
                    } else {
                        // Still measuring: shimmering text and a countdown, no dash.
                        MeasuringLabel(readyAt: pace.readyAt, explain: explain)
                    }
                }
                .fixedSize()
                .contentShape(Rectangle())
                .onHover { h in   // opens from the label…
                    if h, !explain { withAnimation(.smooth(duration: 0.2)) { explain = true } }
                }
                Spacer(minLength: 6)
                if pace.perHour != nil {
                    forecast.font(CardType.caption).tracking(0.05).lineLimit(1).fixedSize()
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            PaceMeter(ratio: pace.ratio, level: pace.level)
                .frame(height: 30)
            if explain {
                Explainer(pace: pace, week: week, now: now)
                    .padding(.top, 2)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onGrow($0 + 8) }
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        // …and stays open while the cursor is anywhere over the pace block,
        // the explainer included, so it can't flicker open/closed.
        .contentShape(Rectangle())
        .onHover { h in
            if !h, explain { withAnimation(.smooth(duration: 0.16)) { explain = false } }
        }
        .onChange(of: explain) { _, on in if !on { onGrow(0) } }
        .onDisappear { onGrow(0) }
    }

    @ViewBuilder private var forecast: some View {
        if let out = pace.runsOutAt {
            let t = out.timeIntervalSince(now)
            Text(t < 24 * 3600 ? "Runs out in ~\(ActivityTracker.Activity.compact(t, floor: 60))"
                               : "Runs out ~\(When.at(out, now: now))")
        } else if let keep = pace.leftAtReset {
            Text(keep < 3 ? "Just enough until reset" : "Enough until reset")
        } else {
            Text("Measuring your pace").foregroundStyle(.white.opacity(0.5)).modifier(Shimmer())
        }
    }
}

enum Pct {
    static func rate(_ r: Double) -> String {
        r < 10 ? String(format: "%.1f%%", r) : "\(Int(r.rounded()))%"
    }
}

/// "Measuring your pace  4:32 ⓘ" — shimmering while the first 10 minutes of
/// readings come in, with a live countdown to the first result.
private struct MeasuringLabel: View {
    let readyAt: Date?
    var explain = false
    @Environment(\.cardShown) private var shown

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Measuring your pace")
                .font(CardType.body)
                .foregroundStyle(.white.opacity(0.55))
                .modifier(Shimmer())
            if let r = readyAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let t = Int(max(0, r.timeIntervalSince(ctx.date)))
                    Text(String(format: "%d:%02d", t / 60, t % 60))
                        .font(CardType.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.smooth(duration: 0.3), value: t)
                }
            }
            Image(systemName: "info.circle")
                .font(CardType.caption)
                .foregroundStyle(.white.opacity(explain ? 0.9 : 0.6))
        }
    }
}

/// Plain words on hover, written to ASD-STE100 (Simplified Technical
/// English): short sentences, present tense, one idea per line.
///
///   You reach the session limit in about 1h 53m.      ← verdict, colored
///   Now    40%/h · last 30 min
///   Safe   33%/h or less · middle of the bar
///   Week   Enough · about 28% stays at the reset
private struct Explainer: View {
    let pace: SessionPace
    let week: WeekOutlook?
    let now: Date

    private let label = Color.white.opacity(0.5)
    private let note = Color.white.opacity(0.62)
    private let value = Color.white

    var body: some View {
        let window = pace.span == .session ? "session" : "week"
        VStack(alignment: .leading, spacing: 6) {
            verdict(window)
                .font(CardType.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                if let r = pace.perHour {
                    row("Now", [(Pct.rate(r) + "/h", value, true), (" · " + basis(window), note, false)])
                }
                if let o = pace.optimal {
                    row("Safe", [(Pct.rate(o) + "/h or less", value, true), (" · middle of the bar", note, false)])
                }
                if let w = week { row("Week", weekParts(w)) }
            }
        }
        .font(CardType.caption)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: lines

    @ViewBuilder private func verdict(_ window: String) -> some View {
        if let out = pace.runsOutAt {
            let t = out.timeIntervalSince(now)
            let when = t < 24 * 3600 ? "in about \(ActivityTracker.Activity.compact(t, floor: 60))"
                                     : "at about \(When.at(out, now: now))"
            text([("You reach the \(window) limit \(when).", pace.level.color, true)])
        } else if let keep = pace.leftAtReset {
            if keep < 3 {
                text([("You have just enough for this \(window).", Theme.green, true)])
            } else {
                text([("You have enough for this \(window). ", Theme.green, true),
                      ("About \(Theme.pct(keep)) stays unused.", note, false)])
            }
        } else {
            let wait = pace.readyAt.map { ActivityTracker.Activity.compact(max(0, $0.timeIntervalSince(now)), floor: 60) } ?? "10m"
            text([("Measuring your pace. ", value, true),
                  ("The first result comes in about \(wait), after 10 minutes of data.", note, false)])
        }
    }

    private func basis(_ window: String) -> String {
        switch pace.basis {
        case .recent(let m): return "last \(m) min"
        case .sinceStart: return "since the \(window) started"
        }
    }

    private func weekParts(_ w: WeekOutlook) -> [(String, Color, Bool)] {
        if let out = w.runsOutAt {
            return [("Not enough", Theme.yellow, true),
                    (" · you reach the limit at about \(When.at(out, now: now))", note, false)]
        }
        if let keep = w.leftAtReset {
            return [("Enough", Theme.green, true), (" · about \(Theme.pct(keep)) stays at the reset", note, false)]
        }
        return [("\(Theme.pct(w.left)) left", value, true)]
    }

    // MARK: building blocks

    private func row(_ name: String, _ parts: [(String, Color, Bool)]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).foregroundStyle(label).frame(width: 32, alignment: .leading)
            text(parts).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One wrapping paragraph with its own color / weight per part.
    private func text(_ parts: [(String, Color, Bool)]) -> Text {
        var a = AttributedString()
        for (str, color, strong) in parts {
            var run = AttributedString(str)
            run.foregroundColor = color
            run.font = strong ? CardType.caption.weight(.medium) : CardType.caption
            a += run
        }
        return Text(a)
    }
}

/// A linear speedometer of the pace (Figma 2190:24011 ticks). The taller
/// middle tick is the optimal pace; ticks light up from there toward the
/// needle: left = slower (white), right = faster (warning color).
private struct PaceMeter: View {
    let ratio: Double?
    let level: UsageLevel

    var body: some View {
        // Needle position 0…1 across the bar: 0.5 = optimal, 1 = 2× faster.
        let pos = ratio.map { min(2, max(0, $0)) / 2 } ?? -1
        let fast = (ratio ?? 0) > 1
        let c: Color = fast ? (level == .critical ? Theme.red : Theme.yellow) : .white
        if ratio == nil {
            // No pace yet: a slow wave of light runs across the ticks.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !shown)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                PaceMeterCanvas(pos: -1, color: .white, wave: t * 1.4 - 0.2)
            }
        } else {
            PaceMeterCanvas(pos: pos, color: c)
                .animation(.spring(duration: 0.6, bounce: 0.2), value: pos)
                .animation(.smooth(duration: 0.4), value: fast)
        }
    }

    @Environment(\.cardShown) private var shown
}

/// False while a card sits hidden in the hover card's stack: its looping
/// animations pause so they cost nothing.
private struct CardShownKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var cardShown: Bool {
        get { self[CardShownKey.self] }
        set { self[CardShownKey.self] = newValue }
    }
}

/// Loading shimmer: a soft band of light sweeping across the content.
struct Shimmer: ViewModifier {
    @Environment(\.cardShown) private var shown

    func body(content: Content) -> some View {
        content.overlay {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !shown)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.9), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(24, g.size.width * 0.6))
                        .offset(x: CGFloat(t * 1.8 - 0.6) * g.size.width)
                }
            }
            .mask(content)
            .allowsHitTesting(false)
        }
    }
}

/// Dashboard-style tick bar (after the car-cluster references): ticks swell
/// and brighten around the needle, lit ones run from the optimal middle to
/// the needle on a gradient, the rest fade out toward the ends. The needle
/// is a thin white line with a dot on top that rises above the ticks.
private struct PaceMeterCanvas: View, Animatable {
    var pos: Double                       // -1 = no needle yet
    var color: Color
    /// While measuring: where the loading wave is, 0…1 across (nil = none).
    var wave: Double? = nil
    var animatableData: Double {
        get { pos }
        set { pos = newValue }
    }

    static let glowRoom: CGFloat = 8

    var body: some View {
        // The canvas reaches `glowRoom` past its layout frame on every side,
        // so the needle's dot and the ticks' glow aren't cut at the edges.
        Canvas { ctx, full in
            ctx.translateBy(x: Self.glowRoom, y: Self.glowRoom)
            let size = CGSize(width: full.width - 2 * Self.glowRoom, height: full.height - 2 * Self.glowRoom)
            let tick: CGFloat = 2, gap: CGFloat = 2
            let n = max(11, Int((size.width + gap) / (tick + gap)) | 1)
            let step = (size.width - tick) / CGFloat(n - 1)
            let mid = n / 2
            let base: CGFloat = size.height - 5          // bottom of the ticks
            let maxH: CGFloat = size.height - 11, minH: CGFloat = maxH * 0.5
            let needle = pos >= 0 ? pos * Double(n - 1) : nil
            func x(_ i: Double) -> CGFloat { CGFloat(i) * step + tick / 2 }

            var lit: [(CGRect, Double)] = []
            for i in 0..<n {
                let d = needle.map { abs(Double(i) - $0) } ?? 99
                let swell = needle != nil ? exp(-pow(d / 10, 2))
                    : wave.map { exp(-pow((Double(i) - $0 * Double(n - 1)) / 8, 2)) } ?? 0.35
                let h = minH + (maxH - minH) * CGFloat(swell)
                let r = CGRect(x: x(Double(i)) - tick / 2, y: base - h, width: tick, height: h)
                let path = Path(roundedRect: r, cornerRadius: 1)
                if let nd = needle, Double(min(mid, Int(nd.rounded()))) <= Double(i),
                   Double(i) <= Double(max(mid, Int(nd.rounded()))) {
                    // From the middle (dim) to the needle (full).
                    let span = max(1, abs(nd - Double(mid)))
                    let t = abs(Double(i) - Double(mid)) / span
                    let a = 0.28 + 0.72 * t
                    lit.append((r, a))
                    ctx.fill(path, with: .color(color.opacity(a)))
                } else {
                    let edge = abs(Double(i - mid)) / Double(mid)          // 0 middle … 1 ends
                    let a = 0.2 * (1 - 0.6 * edge * edge) + 0.16 * swell
                    ctx.fill(path, with: .color(.white.opacity(a)))
                }
            }
            // Soft glow under the lit ticks.
            if !lit.isEmpty {
                ctx.drawLayer { g in
                    g.addFilter(.blur(radius: 4))
                    for (r, a) in lit { g.fill(Path(r.insetBy(dx: -1, dy: 0)), with: .color(color.opacity(a * 0.55))) }
                }
            }
            // Baseline with the optimal mark in the middle.
            let lineY = base + 2.5
            ctx.fill(Path(CGRect(x: 0, y: lineY, width: size.width, height: 1)),
                     with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                            .init(color: .white.opacity(0.18), location: 0.5),
                                                            .init(color: .white.opacity(0), location: 1)]),
                                           startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
            ctx.fill(Path(roundedRect: CGRect(x: x(Double(mid)) - 1, y: lineY - 1, width: 2, height: 4.5), cornerRadius: 1),
                     with: .color(.white.opacity(0.7)))
            // Needle.
            if let nd = needle {
                let nx = x(nd)
                var glow = ctx
                glow.addFilter(.shadow(color: .white.opacity(0.85), radius: 4))
                glow.fill(Path(roundedRect: CGRect(x: nx - 0.75, y: 4, width: 1.5, height: size.height - 4),
                               cornerRadius: 0.75), with: .color(.white))
                glow.fill(Path(ellipseIn: CGRect(x: nx - 2.75, y: 0.5, width: 5.5, height: 5.5)), with: .color(.white))
            }
        }
        .padding(-Self.glowRoom)
    }
}

/// The window is used up: just a live countdown to the reset.
private struct UsedUpSection: View {
    let pace: SessionPace
    let now: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let r = pace.resetsAt {
                    let t = max(0, r.timeIntervalSince(ctx.date))
                    Text(Self.clock(t))
                        .font(.custom("Inter", size: 28).weight(.medium).monospacedDigit())
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.smooth(duration: 0.3), value: Int(t))
                    Text("until reset").font(CardType.caption).foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 6)
                    Text("at \(When.at(r, now: ctx.date))").font(CardType.caption).foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("Waiting for the reset").font(CardType.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    /// 2:14:05 under a day, else "2d 4h".
    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s >= 86400 { return "\(s / 86400)d \((s % 86400) / 3600)h" }
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

/// "◔ Weekly left 59%  ·  ↻ Wed 8:00pm" (Figma 2190:23975, plans with a session).
private struct WeeklyRow: View {
    let window: LimitWindow

    private var left: Double { max(0, 100 - window.usedPercent) }
    private var level: UsageLevel {
        left <= 10 ? .critical : left <= 30 ? .warning : .normal
    }

    var body: some View {
        HStack(spacing: 4) {
            Ring(fraction: left / 100, color: level.color.opacity(level == .normal ? 0.9 : 1))
                .frame(width: 11, height: 11)
                .padding(.trailing, 1)
            Text("Weekly left").foregroundStyle(.white.opacity(0.62))
            Text(Theme.pct(left))
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.numericText(value: left))
            Spacer(minLength: 6)
            if let r = window.resetsAt {
                Image(systemName: "arrow.clockwise").font(CardType.caption)
                Text(When.day.string(from: r))
            }
        }
        .font(CardType.caption).tracking(0.05)
        .foregroundStyle(.white.opacity(0.62))
    }
}

private struct Ring: View {
    let fraction: Double
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 2)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth(duration: 0.45), value: fraction)
    }
}

private struct OtherRow: View {
    let window: LimitWindow
    var body: some View {
        HStack {
            Text("\(WindowMath.label(window.span)) left").foregroundStyle(.white.opacity(0.62))
            Spacer()
            Text(Theme.pct(max(0, 100 - window.usedPercent))).foregroundStyle(.white.opacity(0.9))
        }
        .font(CardType.caption)
    }
}

enum WindowMath {
    static func length(_ span: LimitWindow.Span) -> TimeInterval? {
        switch span {
        case .session: return 5 * 3600
        case .weekly: return 7 * 86400
        case .other: return nil
        }
    }
    static func label(_ span: LimitWindow.Span) -> String {
        switch span {
        case .session: return "Session"
        case .weekly: return "Weekly"
        case .other(let s): return s
        }
    }
}

struct StateNote: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CardType.body).foregroundStyle(.white.opacity(0.9))
                Text(detail).font(CardType.caption).foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
