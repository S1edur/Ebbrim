import SwiftUI

/// The minimal edge notch (Figma 2179:831): a black pill hugging the screen
/// edge with one vertical usage bar per provider and a servers chip. While a
/// session is burning tokens, the provider's block grows sideways into a
/// Dynamic-Island-style bulge with "30% used in 1h · Session resets in 5h".
///
/// Drawn for the LEFT edge; on the right edge the layout direction is flipped,
/// so "leading" is always the screen edge.
struct NotchColumn: View {
    let items: [NotchLayout.PillItem]
    let serverCount: Int
    let activity: ActivityTracker.Activity?
    let right: Bool
    /// 0 = docked on its edge, 1 = lifted off it while dragged (fully round, no flares).
    var detach: CGFloat = 0
    /// Each provider's level (same as its hover card): sets the pill colors.
    var levels: [ProviderKind: UsageLevel] = [:]

    @State private var bulgeW: CGFloat = 130
    @State private var lastPanel = IslandPanel(rect: .zero, radius: 12)

    private typealias L = NotchLayout

    private var expandedIndex: Int? {
        guard let a = activity else { return nil }
        return items.firstIndex { if case .provider(let p) = $0 { return p.kind == a.kind }; return false }
    }

    var body: some View {
        VStack(spacing: L.blockGap) {
            ForEach(items) { item in
                switch item {
                case .provider(let p), .setup(let p):
                    ProviderBlock(provider: p, level: levels[p.kind] ?? .normal,
                                  activity: activity?.kind == p.kind ? activity : nil,
                                  onBulgeWidth: { bulgeW = $0 })
                case .servers:
                    ServersChip(count: serverCount)
                case .connect(let k):
                    NotchChip(dim: true) {
                        Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    } icon: {
                        ProviderLogo(kind: k, color: Theme.notchMuted)
                    }
                case .settings:
                    GearChip(size: 24)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.6, anchor: .top))
                    .animation(.spring(duration: 0.3, bounce: 0.2).delay(0.04)),
                removal: .opacity.animation(.smooth(duration: 0.1))))
        }
        .padding(.top, L.startPad(items, false))
        .padding(.bottom, L.padBottom)
        .padding(.leading, L.padEdge)
        .padding(.trailing, L.padInner)
        .frame(width: L.columnWidth, height: L.columnH(items), alignment: .top)
        .background(
            NotchShape(radius: L.cornerRadius,
                       panel: currentPanel ?? lastPanel,
                       progress: currentPanel == nil ? 0 : 1,
                       detach: detach)
                .fill(Color.black)
                .scaleEffect(x: right ? -1 : 1)          // mirror for the right edge
                .environment(\.layoutDirection, .leftToRight)
        )
        .environment(\.layoutDirection, right ? .rightToLeft : .leftToRight)
        .onChange(of: currentPanel) { _, new in if let new { lastPanel = new } }
    }

    /// What the island grows into right now: the activity bulge, if any.
    /// nil = just the pill (the last panel is kept so the shape can animate
    /// back into the pill).
    private var currentPanel: IslandPanel? {
        if expandedIndex != nil { return IslandPanel(rect: bulgeRect, radius: 12) }
        return nil
    }

    /// The bulge, in column coordinates (left-edge frame): it covers the
    /// expanded block's info rows.
    private var bulgeRect: CGRect {
        let blockTop = L.itemTop(expandedIndex ?? 0, items)
        let infoTop = blockTop + L.blockH - L.infoH
        let colH = L.columnH(items)
        let top = infoTop - 6
        var bottom = min(colH, blockTop + L.blockH + 7)
        // Too close to the pill's end for a fillet: run the bulge flush to it.
        if colH - bottom < L.cornerRadius + 17.5 { bottom = colH }
        return CGRect(x: 0, y: top, width: L.padEdge + bulgeW + L.padInner, height: bottom - top)
    }
}

// MARK: - Provider block

private struct ProviderBlock: View {
    let provider: ProviderUsage
    var level: UsageLevel = .normal
    let activity: ActivityTracker.Activity?
    let onBulgeWidth: (CGFloat) -> Void

    private typealias L = NotchLayout
    private var style: ProviderStyle { .of(provider, level: level) }  // bar, %, logo share it

    var body: some View {
        if L.isCompact(provider) {
            // Nothing to measure yet: just the logo and why, in a small chip.
            NotchChip(dim: true) {
                label
            } icon: {
                ProviderLogo(kind: provider.kind, color: Theme.notchMuted)
            }
        } else {
            barBlock
        }
    }

    private var barBlock: some View {
        VStack(spacing: 4) {
            UsageBar(fraction: barFraction, fill: style.fill)
                .frame(height: activity == nil ? L.barH : L.barH - (L.infoH - L.labelH))
                .opacity(style.dim)
                .frame(maxWidth: .infinity)

            if let a = activity {
                info(a)
                    .frame(width: L.contentW, height: L.infoH, alignment: .leading)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading))
                            .animation(.smooth(duration: 0.22).delay(0.05)),
                        removal: .opacity.animation(.smooth(duration: 0.09))))
            } else {
                VStack(spacing: 2) {
                    label.frame(height: 12)
                    ProviderLogo(kind: provider.kind, color: style.label).opacity(style.dim)
                }
                .frame(height: L.labelH)
                .transition(.opacity.animation(.smooth(duration: 0.15)))
            }
        }
        .frame(height: L.blockH)
    }

    /// Bars run 0…100 %; above 100 the bar is simply full.
    private var barFraction: CGFloat {
        switch provider.freshness {
        case .live, .stale: return CGFloat(provider.leftPercent ?? 0) / 100
        case .needsSetup, .unavailable: return 0
        }
    }

    @ViewBuilder private var label: some View {
        switch provider.freshness {
        case .live, .stale:
            Text(provider.leftPercent.map(Theme.pct) ?? "—")
                .font(Theme.notchFont)
                .foregroundStyle(style.label)
                .opacity(style.dim)
                .fixedSize()
        case .needsSetup:
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.notchMuted)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.yellow)
        }
    }

    /// The bulge content: badge + logo row. Wider than the column on purpose.
    /// The island is an alert: yellow when the session is at risk, red when critical.
    private func info(_ a: ActivityTracker.Activity) -> some View {
        let c = a.severity == .critical ? Theme.red : Theme.yellow
        return VStack(alignment: .leading, spacing: 4) {
            Text(a.headline)
                .font(Theme.notchFont.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .frame(minWidth: 126, maxWidth: .infinity)     // spans the bulge
                .background(c.opacity(a.severity == .critical ? 0.45 : 0.32),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 10) {
                ProviderLogo(kind: provider.kind, color: c)
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(a.resetText(now: ctx.date))
                        .font(Theme.notchFont)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 2)
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { onBulgeWidth($0) }
    }
}

/// Vertical capsule bar filling from the bottom.
private struct UsageBar: View {
    let fraction: CGFloat
    let fill: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.notchTrack)
                if fraction > 0 {
                    Capsule().fill(fill)
                        .frame(height: max(NotchLayout.barW, h * fraction))
                }
            }
            .animation(.easeInOut(duration: 0.5), value: fraction)
        }
        .frame(width: NotchLayout.barW)
    }
}

private struct ServersChip: View {
    let count: Int
    var body: some View {
        NotchChip(dim: count == 0) {
            Text(verbatim: "\(count)")
                .font(Theme.notchFont)
                .foregroundStyle(.white.opacity(count == 0 ? 0.45 : 0.75))
        } icon: {
            Image(nsImage: Marks.database).resizable().frame(width: 16, height: 16)
        }
    }
}

/// Settings, at the end of the pill while it's hovered.
struct GearChip: View {
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .frame(height: max(size, NotchLayout.gearH))
            .contentShape(Rectangle())
    }
}

/// The small rounded chip of the notch: a 12 pt line over a 16 pt icon.
/// `dim` = nothing there yet (no servers, provider not set up).
struct NotchChip<Top: View, Icon: View>: View {
    var dim = false
    @ViewBuilder var top: Top
    @ViewBuilder var icon: Icon
    var body: some View {
        VStack(spacing: 2) {
            top.frame(height: 12)
            icon.opacity(dim ? 0.8 : 1)
        }
        .padding(4)
        .background(Color.white.opacity(dim ? 0.05 : 0.08),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .frame(height: NotchLayout.chipH)
    }
}

// MARK: - Colors per provider and state

struct ProviderStyle {
    var fill: Color
    var label: Color
    var badge: Color
    var dim: Double

    /// One color story per state, like the hover card: the bar shows what's
    /// LEFT; plenty left is calm grey, then yellow, then red. Bar fill,
    /// percentage and logo all agree.
    static func of(_ p: ProviderUsage, level: UsageLevel = .normal) -> ProviderStyle {
        var s: ProviderStyle
        switch level {
        case .normal:
            s = ProviderStyle(fill: .white.opacity(0.42), label: Color(white: 0.66),
                              badge: .white.opacity(0.12), dim: 1)
        case .warning:
            s = ProviderStyle(fill: Theme.yellow, label: Theme.yellow, badge: Theme.yellow.opacity(0.2), dim: 1)
        case .critical:
            s = ProviderStyle(fill: Theme.red, label: Theme.red, badge: Theme.red.opacity(0.2), dim: 1)
        }
        let freshness = p.freshness
        switch freshness {
        case .live: break
        case .stale: s.dim = 0.85             // older numbers: barely quieter, still readable
        case .needsSetup, .unavailable:
            s.dim = 0.85; s.label = Theme.notchMuted; s.fill = Theme.notchMuted
        }
        return s
    }
}

// MARK: - Shape

/// What the pill grows into: a rect in column coordinates (left-edge frame,
/// x from 0 = screen edge to the panel's outer edge) and its corner radius.
struct IslandPanel: Equatable {
    var rect: CGRect
    var radius: CGFloat
}

/// Pill hugging the left screen edge (rounded on the inner side) that can
/// grow a panel out of its inner side, joined by concave fillets like two iOS
/// Dynamic Island blobs merging. The same shape serves the small activity
/// bulge and the full hover panel, so one morphs into the other.
///
/// At each junction (top, bottom) the fillet sits on the panel side when the
/// panel edge is within the pill, and on the pill side when the panel
/// reaches past it; radii shrink to zero as the two edges line up.
struct NotchShape: Shape {
    var radius: CGFloat
    var panel: IslandPanel
    var progress: CGFloat
    var detach: CGFloat = 0                // 0 docked … 1 lifted: edge corners round, flares go
    var fillet: CGFloat = 17.5             // Figma "Vector 2697" corner size
    var edgeFillet: CGFloat = 10           // Figma "Vector 2699": pill flares into the screen edge

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>,
                                       AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(AnimatablePair(AnimatablePair(progress, panel.radius), detach),
                           AnimatablePair(panel.rect.minY,
                                          AnimatablePair(panel.rect.height, panel.rect.maxX)))
        }
        set {
            progress = newValue.first.first.first
            panel.radius = newValue.first.first.second
            detach = newValue.first.second
            let maxX = newValue.second.second.second
            panel.rect = CGRect(x: 0, y: newValue.second.first,
                                width: maxX, height: newValue.second.second.first)
        }
    }

    /// How one junction (top or bottom) between pill and panel is drawn.
    /// `d` = how far the panel edge sits inside the pill (negative: it reaches
    /// past it). The radii shrink smoothly with |d|, so the outline always
    /// hugs the panel exactly: no snapping, no dead black space.
    private struct Join {
        var pillCorner: CGFloat     // pill's inner corner at this end
        var fillet: CGFloat         // concave join
        var panelCorner: CGFloat    // panel's corner next to the pill
        var outside: Bool           // fillet on the pill side (panel reaches past)

        init(d: CGFloat, r: CGFloat, f: CGFloat, pr: CGFloat) {
            if d >= 0 {
                let full = r + f
                let s = full > 0 ? min(1, d / full) : 0
                pillCorner = r * s; fillet = f * s; panelCorner = 0; outside = false
            } else {
                let full = f + pr
                let s = full > 0 ? min(1, -d / full) : 0
                pillCorner = 0; fillet = f * s; panelCorner = pr * s; outside = true
            }
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = min(radius, w / 2, h / 2)
        // Let the spring overshoot a touch (size only), so opening has the
        // iOS bounce; fillets and radii stay capped.
        let pe = max(0, min(1.08, progress))
        let p = min(1, pe)
        let er = r * max(0, min(1, detach))          // edge-side corners
        func pill(top: CGFloat, bottom: CGFloat, y0: CGFloat = 0, y1: CGFloat? = nil) -> Path {
            Path(roundedRect: CGRect(x: 0, y: y0, width: w, height: (y1 ?? h) - y0),
                 cornerRadii: RectangleCornerRadii(topLeading: er, bottomLeading: er,
                                                   bottomTrailing: bottom, topTrailing: top),
                 style: .continuous)
        }
        guard p > 0.001, panel.rect.maxX > w + 0.5 else {
            return pill(top: r, bottom: r).union(edgeFlares(top: 0, bottom: h))
        }

        // Grow out of the pill: width and height ease from the pill toward the target.
        let ext = w + (panel.rect.maxX - w) * pe
        // Start (and end) as a small round nub at the panel's middle, so it
        // blooms out of the pill and shrinks back like an iOS island.
        let midY = min(max(panel.rect.midY, r), h - r)
        let nub = min(panel.rect.height, 2 * r)
        let t0 = midY - nub / 2, b0 = midY + nub / 2
        var t = t0 + (panel.rect.minY - t0) * pe
        var b = b0 + (panel.rect.maxY - b0) * pe
        // A panel edge just inside the pill's end would leave a tiny ledge:
        // run it flush instead (a few points of extra padding).
        let snap: CGFloat = 14
        if t > 0, t < snap { t = 0 }
        if h - b > 0, h - b < snap { b = h }
        // A panel reaching only a little past the pill would leave a stair:
        // stretch the pill along the screen edge to meet it instead.
        let reach: CGFloat = 30
        var pt: CGFloat = 0, pb = h
        if t < 0, t > -reach { pt = t }
        if b > h, b < h + reach { pb = b }
        let f = min(fillet * p, ext - w)
        let pr = min(panel.radius, (b - t) / 2, ext - w)   // only the outer corners round

        let top = Join(d: t - pt, r: r, f: f, pr: pr)
        let bot = Join(d: pb - b, r: r, f: f, pr: pr)

        var shape = pill(top: top.pillCorner, bottom: bot.pillCorner, y0: pt, y1: pb)
            .union(edgeFlares(top: pt, bottom: pb))
        let body = Path(roundedRect: CGRect(x: w - 1, y: t, width: ext - w + 1, height: b - t),
                        cornerRadii: RectangleCornerRadii(
                            topLeading: top.panelCorner, bottomLeading: bot.panelCorner,
                            bottomTrailing: pr, topTrailing: pr),
                        style: .continuous)
        shape = shape.union(body)

        // Fillets, from the Figma corner curve (0,17.5)→(17.5,0), c1 (0,5.5), c2 (11.667,0.833).
        var j = Path()
        if top.fillet > 0.5 {
            let f = top.fillet, k = f / 17.5
            if top.outside {   // corner at (w, pt), opening left/up
                j.move(to: CGPoint(x: w, y: pt - f))
                j.addCurve(to: CGPoint(x: w - f, y: pt),
                           control1: CGPoint(x: w, y: pt - 5.5 * k),
                           control2: CGPoint(x: w - 11.667 * k, y: pt - 0.833 * k))
                j.addLine(to: CGPoint(x: w + 0.5, y: pt + 0.5))
            } else {           // corner at (w, t), opening right/up
                j.move(to: CGPoint(x: w, y: t - f))
                j.addCurve(to: CGPoint(x: w + f, y: t),
                           control1: CGPoint(x: w, y: t - 5.5 * k),
                           control2: CGPoint(x: w + 11.667 * k, y: t - 0.833 * k))
                j.addLine(to: CGPoint(x: w - 0.5, y: t + 0.5))
            }
            j.closeSubpath()
        }
        if bot.fillet > 0.5 {
            let f = bot.fillet, k = f / 17.5
            if bot.outside {   // corner at (w, pb), opening left/down
                j.move(to: CGPoint(x: w - f, y: pb))
                j.addCurve(to: CGPoint(x: w, y: pb + f),
                           control1: CGPoint(x: w - 11.667 * k, y: pb + 0.833 * k),
                           control2: CGPoint(x: w, y: pb + 5.5 * k))
                j.addLine(to: CGPoint(x: w + 0.5, y: pb - 0.5))
            } else {           // corner at (w, b), opening right/down
                j.move(to: CGPoint(x: w + f, y: b))
                j.addCurve(to: CGPoint(x: w, y: b + f),
                           control1: CGPoint(x: w + 11.667 * k, y: b + 0.833 * k),
                           control2: CGPoint(x: w, y: b + 5.5 * k))
                j.addLine(to: CGPoint(x: w - 0.5, y: b - 0.5))
            }
            j.closeSubpath()
        }
        return shape.union(j)
    }

    /// Concave flares where the pill meets the screen edge, above and below it
    /// (Figma curve (0,10)→(10,0), c1 (0,3.143), c2 (6.667,0.476)).
    private func edgeFlares(top: CGFloat, bottom: CGFloat) -> Path {
        let e = edgeFillet * (1 - max(0, min(1, detach))), k = e / 10
        var j = Path()
        guard e > 0.3 else { return j }
        j.move(to: CGPoint(x: 0, y: top - e))
        j.addCurve(to: CGPoint(x: e, y: top),
                   control1: CGPoint(x: 0, y: top - 3.143 * k),
                   control2: CGPoint(x: 6.667 * k, y: top - 0.476 * k))
        j.addLine(to: CGPoint(x: e, y: top + 0.5))
        j.addLine(to: CGPoint(x: 0, y: top + 0.5)); j.closeSubpath()
        j.move(to: CGPoint(x: e, y: bottom))
        j.addCurve(to: CGPoint(x: 0, y: bottom + e),
                   control1: CGPoint(x: 6.667 * k, y: bottom + 0.476 * k),
                   control2: CGPoint(x: 0, y: bottom + 3.143 * k))
        j.addLine(to: CGPoint(x: 0, y: bottom - 0.5))
        j.addLine(to: CGPoint(x: e, y: bottom - 0.5)); j.closeSubpath()
        return j
    }
}

// MARK: - Bottom edge (horizontal pill)

/// The same pill lying along the bottom edge (Figma 2190:23944): blocks left
/// to right, each a logo and its number next to a short horizontal bar. The
/// shape is the side-edge NotchShape turned a quarter (screen edge at the bottom).
struct NotchRow: View {
    let items: [NotchLayout.PillItem]
    let serverCount: Int
    var detach: CGFloat = 0
    var levels: [ProviderKind: UsageLevel] = [:]

    private typealias L = NotchLayout

    var body: some View {
        let len = L.pillLength(items, true), t = L.thickness(true)
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                Group {
                    switch item {
                    case .provider(let p), .setup(let p): RowBlock(provider: p, level: levels[p.kind] ?? .normal)
                    case .settings: GearChip(size: L.rowItemH)
                    case .connect(let k): RowChip(dim: true, width: L.rowSmallW) {
                        Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    } icon: {
                        ProviderLogo(kind: k, color: Theme.notchMuted)
                    }
                    case .servers: RowChip(dim: serverCount == 0) {
                        Text(verbatim: "\(serverCount)").font(Theme.notchFont.monospacedDigit())
                            .foregroundStyle(.white.opacity(serverCount == 0 ? 0.45 : 0.75))
                            .fixedSize()
                    } icon: {
                        Image(nsImage: Marks.database).resizable().frame(width: 16, height: 16)
                    }
                    }
                }
                .frame(width: item.width, height: L.rowItemH, alignment: .leading)
                .padding(.leading, L.gapBefore(i, items, true))
                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
            }
        }
        .padding(.leading, L.startPad(items, true))
        .padding(.trailing, L.padEnd(true))
        .frame(width: len, height: t, alignment: .leading)
        .background {
            // Corner = chip corner 7 + inset 4, so the last chip's corner runs
            // parallel to the pill's: the same 4 pt gap all the way round.
            // (While dragged it rounds fully into a capsule.)
            NotchShape(radius: L.rowCorner + (t / 2 - L.rowCorner) * detach,
                       panel: IslandPanel(rect: .zero, radius: 12), progress: 0, detach: detach)
                .fill(Color.black)
                .frame(width: t, height: len)
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct RowBlock: View {
    let provider: ProviderUsage
    var level: UsageLevel = .normal
    private var style: ProviderStyle { .of(provider, level: level) }

    var body: some View {
        if NotchLayout.isCompact(provider) {
            RowChip(dim: true, width: NotchLayout.rowSmallW) {
                if case .unavailable = provider.freshness {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.yellow)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.notchMuted)
                }
            } icon: {
                ProviderLogo(kind: provider.kind, color: Theme.notchMuted)
            }
        } else {
            // Hugs its content (width measured in NotchLayout.rowBlockW): the bar
            // follows the number at 5 pt and nothing is left over at the end.
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    ProviderLogo(kind: provider.kind, color: style.label)
                    Text(NotchLayout.rowLabel(provider))
                        .font(Font(NotchLayout.rowFont)).foregroundStyle(style.label)
                        .fixedSize()
                }
                .opacity(style.dim)
                .padding(.trailing, 5)
                let f = CGFloat(provider.leftPercent ?? 0) / 100
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.notchTrack)
                    if f > 0 { Capsule().fill(style.fill).frame(width: max(NotchLayout.barW, 42 * f)) }
                }
                .frame(width: 42, height: NotchLayout.barW)
                .opacity(style.dim)
                .animation(.easeInOut(duration: 0.5), value: f)
            }
        }
    }
}

/// Horizontal twin of NotchChip: a short line, then the icon.
private struct RowChip<Top: View, Icon: View>: View {
    var dim = false
    var width: CGFloat = NotchLayout.rowChipW
    @ViewBuilder var top: Top
    @ViewBuilder var icon: Icon
    var body: some View {
        HStack(spacing: 3) {
            top
            icon.opacity(dim ? 0.8 : 1)
        }
        .frame(width: width, height: NotchLayout.rowItemH)
        .background(Color.white.opacity(dim ? 0.05 : 0.08),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
