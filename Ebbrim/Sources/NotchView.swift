import SwiftUI
import AppKit

/// Single source of truth for where the pill and the hover card sit inside
/// the full-screen panel (panel-local, top-left points). The view uses it to
/// place things and the controller uses it to hit-test, so they can never
/// disagree. The pill runs along its edge: vertically on the left / right,
/// horizontally on the bottom ("along" = the edge's direction).
enum NotchLayout {
    static let maxRows = 8

    // Minimal notch column (Figma 2179:831). Fixed sizes, so the
    // controller's hit-testing always matches what's drawn.
    static let columnWidth: CGFloat = 34      // pill thickness, on every edge
    static let cornerRadius: CGFloat = 18
    static let padTop: CGFloat = 12
    static let padBottom: CGFloat = 8
    static let padEdge: CGFloat = 6           // screen-edge side
    static let padInner: CGFloat = 8
    static var contentW: CGFloat { columnWidth - padEdge - padInner }
    static let blockH: CGFloat = 76           // bar + label + logo
    static let blockGap: CGFloat = 10
    static let barW: CGFloat = 5
    static let labelH: CGFloat = 30           // "20%" 12 + 2 + logo 16
    static let barH: CGFloat = blockH - 4 - labelH
    static let infoH: CGFloat = 40            // expanded: badge 20 + 4 + row 16
    static let chipH: CGFloat = 38
    static let gearH: CGFloat = 32
    /// Settings choices (from NotchModel): what the pill leaves out.
    nonisolated(unsafe) static var hiddenKinds: Set<ProviderKind> = []
    nonisolated(unsafe) static var showServers = true
    /// Providers disconnected in Settings › Sources (from feed.settings).
    nonisolated(unsafe) static var disabledKinds: Set<ProviderKind> = []
    // Bottom edge (horizontal pill)
    // Bottom row: every element is 22 pt tall, centered in a 30 pt pill with
    // equal ends, so the row reads balanced (logo 16 + 4 + "100%" ≤26 + 5 + bar 42).
    /// The bottom row's number font (Inter 10, tabular digits). The same
    /// NSFont draws the label and measures it, so a block hugs its content.
    static let rowFont: NSFont = {
        let base = NSFont(name: "Inter", size: 10) ?? .systemFont(ofSize: 10)
        let tnum: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kNumberSpacingType,
                                                         .selectorIdentifier: kMonospacedNumbersSelector]
        let d = base.fontDescriptor.addingAttributes([.featureSettings: [tnum]])
        return NSFont(descriptor: d, size: 10) ?? base
    }()
    static func rowLabel(_ p: ProviderUsage) -> String { p.leftPercent.map(Theme.pct) ?? "—" }
    /// logo 16 + 4 + number + 5 + bar 42, nothing spare.
    static func rowBlockW(_ p: ProviderUsage) -> CGFloat {
        let w = (rowLabel(p) as NSString).size(withAttributes: [.font: rowFont]).width
        return 16 + 4 + ceil(w) + 5 + 42
    }
    static let rowChipW: CGFloat = 40
    static let rowSmallW: CGFloat = 34            // "+ logo" / "⚠ logo"
    static let rowItemH: CGFloat = 22
    static var rowCorner: CGFloat { 7 + (thickness(true) - rowItemH) / 2 }   // 11
    /// Pill thickness across its edge: 34 on the sides, 28 on the bottom.
    static func thickness(_ h: Bool) -> CGFloat { h ? 30 : columnWidth }
    /// How far the pill lifts off its edge while dragged.
    static let lift: CGFloat = 12

    static func horizontal(_ e: Edge) -> Bool { e == .bottom }

    /// Providers with nothing to show (needs setup / unavailable) collapse to
    /// a small chip; ones with numbers get the full bar block.
    static func isCompact(_ p: ProviderUsage) -> Bool {
        switch p.freshness {
        case .live, .stale: return false
        case .needsSetup, .unavailable: return true
        }
    }
    static func blockH(_ p: ProviderUsage) -> CGFloat { isCompact(p) ? chipH : blockH }

    /// One block of the pill, in reading order. Each block is its own hover
    /// zone and points the card at its own content.
    enum PillItem: Identifiable, Equatable {
        case provider(ProviderUsage)     // bar block, or ⚠ chip when unavailable
        case servers
        case setup(ProviderUsage)        // "+" chip, shown only while hovering
        case connect(ProviderKind)       // "+ logo": disconnected in Settings; a click reconnects
        case settings                    // gear, shown only while hovering (last)

        var id: String {
            switch self {
            case .provider(let p): return "p.\(p.kind.rawValue)"
            case .servers: return "servers"
            case .setup(let p): return "s.\(p.kind.rawValue)"
            case .connect(let k): return "c.\(k.rawValue)"
            case .settings: return "settings"
            }
        }
        var panel: ActivePanel {
            switch self {
            case .provider(let p), .setup(let p): return .provider(p.kind)
            case .servers: return .servers
            case .settings, .connect: return .settings      // no card: the pill just stays open
            }
        }
        var height: CGFloat {
            switch self {
            case .provider(let p): return NotchLayout.blockH(p)
            case .servers, .setup, .connect: return NotchLayout.chipH
            case .settings: return NotchLayout.gearH
            }
        }
        var width: CGFloat {
            switch self {
            case .provider(let p): return NotchLayout.isCompact(p) ? NotchLayout.rowSmallW : NotchLayout.rowBlockW(p)
            case .servers: return NotchLayout.rowChipW
            case .setup, .connect: return NotchLayout.rowSmallW
            case .settings: return NotchLayout.rowItemH
            }
        }
        /// A small chip (servers, setup "+", ⚠, gear) rather than a bar block.
        var isChip: Bool {
            if case .provider(let p) = self { return NotchLayout.isCompact(p) }
            return true
        }
        func length(_ h: Bool) -> CGFloat { h ? width : height }
        /// Ignores the numbers, so the layout only animates on shape changes.
        var layoutKey: String {
            if case .provider(let p) = self { return id + ":\(NotchLayout.isCompact(p))" }
            return id
        }
    }

    /// Pill content. A provider that only needs setup has nothing to say at a
    /// glance: its "+" chip joins at the very end while the notch is hovered
    /// (after everything, so nothing under the cursor moves).
    /// A disconnected provider gets a "+ logo" chip at the same place as a
    /// "+" setup chip; one only hidden in Appearance shows nothing at all.
    static func items(_ all: [ProviderUsage], hovering: Bool) -> [PillItem] {
        let all = all.filter { !hiddenKinds.contains($0.kind) && !disabledKinds.contains($0.kind) }
        let setup = all.filter { if case .needsSetup = $0.freshness { return true }; return false }
        let shown = all.filter { p in !setup.contains { $0.kind == p.kind } }
        let reconnect = ProviderKind.allCases.filter { disabledKinds.contains($0) && !hiddenKinds.contains($0) }
        var items = shown.map(PillItem.provider) + (showServers ? [.servers] : [])
        if hovering || shown.isEmpty {
            items += setup.map(PillItem.setup)
            items += reconnect.map(PillItem.connect)
        }
        // With everything turned off, the gear stays so Settings is reachable.
        if hovering || items.isEmpty { items.append(.settings) }
        return items
    }

    /// Bottom row ends match its top: the logo sits 7 pt in (its top gap),
    /// a closing chip 4 pt in (the chips' top gap).
    static func padStart(_ h: Bool) -> CGFloat { h ? (thickness(true) - 16) / 2 : padTop }
    /// Space before the first item. A boxed chip opening the pill (servers
    /// only, "+" only) sits as close as the closing one does, so both ends match.
    static func startPad(_ items: [PillItem], _ h: Bool) -> CGFloat {
        guard let first = items.first, first.isChip else { return padStart(h) }
        return h ? (thickness(true) - rowItemH) / 2 : padBottom
    }
    static func padEnd(_ h: Bool) -> CGFloat { h ? 14 : padBottom }
    static func gap(_ h: Bool) -> CGFloat { h ? 14 : blockGap }

    /// Space before item `i`. On the bottom row, chips sitting next to each
    /// other (servers, "+", gear) huddle closer than the bar blocks.
    static func gapBefore(_ i: Int, _ items: [PillItem], _ h: Bool) -> CGFloat {
        guard i > 0 else { return 0 }
        if h, items[i].isChip, items[i - 1].isChip { return 6 }
        return gap(h)
    }
    /// Start of item `i` along the pill, from the pill's start.
    static func itemStart(_ i: Int, _ items: [PillItem], _ h: Bool) -> CGFloat {
        startPad(items, h) + (0..<i).map { items[$0].length(h) + gapBefore($0 + 1, items, h) }.reduce(0, +)
    }
    static func pillLength(_ items: [PillItem], _ h: Bool) -> CGFloat {
        guard !items.isEmpty else { return padStart(h) + padEnd(h) }
        // A chip has its own box: it sits closer to the pill's end, so the
        // gap to the edge looks the same as on the side with the bare logo.
        // Ends mirror each other: a bare bar closes like the bare logo opens
        // (7 pt), a boxed chip sits at its own top gap (4 pt).
        let end = !h ? padEnd(h) : items.last!.isChip ? (thickness(true) - rowItemH) / 2 : padStart(h)
        return itemStart(items.count - 1, items, h) + items.last!.length(h) + end
    }
    // Vertical shorthands (the activity bulge lives on the side edges only).
    static func itemTop(_ i: Int, _ items: [PillItem]) -> CGFloat { itemStart(i, items, false) }
    static func columnH(_ items: [PillItem]) -> CGFloat { pillLength(items, false) }

    /// The item under `s` (along the pill, from its start), with hysteresis:
    /// the current item keeps the cursor until it is `dead` points past its edge.
    static func item(at s: CGFloat, _ items: [PillItem], current: ActivePanel, _ h: Bool) -> PillItem? {
        let dead: CGFloat = 8, g = gap(h)
        for (i, it) in items.enumerated() where it.panel == current {
            let a = itemStart(i, items, h)
            if s >= a - g / 2 - dead, s <= a + it.length(h) + g / 2 + dead { return it }
        }
        for (i, it) in items.enumerated() where s < itemStart(i, items, h) + it.length(h) + g / 2 {
            return it
        }
        return items.last
    }
    /// Middle of the item that opens `panel`, from the pill's start.
    static func anchor(_ panel: ActivePanel, _ items: [PillItem], _ h: Bool) -> CGFloat? {
        guard let i = items.firstIndex(where: { $0.panel == panel }) else { return nil }
        return itemStart(i, items, h) + items[i].length(h) / 2
    }

    static func clampFrac(_ f: CGFloat) -> CGFloat { min(0.92, max(0.08, f)) }

    /// The docked pill. Its start stays put while hover-only blocks are
    /// appended, so it only grows away from the start (down / right).
    /// `frac`: from the bottom on the side edges, from the left on the bottom.
    static func pillRect(edge: Edge, providers: [ProviderUsage], hovering: Bool,
                         frac: CGFloat, size: CGSize) -> CGRect {
        let h = horizontal(edge)
        let base = pillLength(items(providers, hovering: false), h)
        let len = pillLength(items(providers, hovering: hovering), h)
        if h {
            let cx = clampFrac(frac) * size.width
            let t = thickness(true)
            return CGRect(x: cx - base / 2, y: size.height - t, width: len, height: t)
        }
        let cy = (1 - clampFrac(frac)) * size.height
        let x = edge == .right ? size.width - columnWidth : 0
        return CGRect(x: x, y: cy - base / 2, width: columnWidth, height: len)
    }

    /// Rough height of a card, only used before its first layout.
    static func cardEstimate(_ active: ActivePanel, serverCount n: Int) -> CGFloat {
        switch active {
        case .none, .settings: return 0
        case .provider: return 150
        case .servers: return n == 0 ? 100 : 64 + CGFloat(min(n, maxRows)) * 40
        }
    }

    /// The hover card: a separate rounded card a few points off the pill,
    /// centered on the hovered block and kept inside the screen.
    static func cardRect(active: ActivePanel, edge: Edge, providers: [ProviderUsage], hovering: Bool,
                         serverCount: Int, measured: CGFloat?, grow: CGFloat = 0,
                         frac: CGFloat, size: CGSize) -> CGRect {
        let ch = measured ?? cardEstimate(active, serverCount: serverCount)
        let base = max(0, ch - grow)          // placed by its size without the bottom extra
        let w = CardMetrics.width, g = CardMetrics.gap, m: CGFloat = 10
        let h = horizontal(edge)
        let pr = pillRect(edge: edge, providers: providers, hovering: hovering, frac: frac, size: size)
        let its = items(providers, hovering: hovering)
        let a = anchor(active, its, h) ?? pillLength(its, h) / 2
        if h {
            let x = min(max(pr.minX + a - w / 2, m), size.width - w - m)
            return CGRect(x: x, y: pr.minY - g - ch, width: w, height: ch)
        }
        let y = min(max(pr.minY + a - base / 2, m), size.height - ch - m)
        let x = edge == .right ? pr.minX - g - w : pr.maxX + g
        return CGRect(x: x, y: y, width: w, height: ch)
    }
}

/// Full-screen, click-through layer. The pill rides its edge at
/// model.centerFrac; hovering a block opens ONE card next to it, which then
/// slides and reshapes to whichever block the cursor moves to. Dragging
/// lifts the pill off the edge as a free capsule that docks to the nearest
/// edge (left, right or bottom) on release.
struct NotchView: View {
    @ObservedObject var feed: UsageFeed
    @ObservedObject var activity: ActivityTracker
    @ObservedObject var servers: ServerStore
    @ObservedObject var model: NotchModel
    let onOpen: (LocalServer) -> Void
    let onKill: (LocalServer) -> Void

    private var hovering: Bool { model.active != .none && !model.dragging }
    /// The edge the pill is shaped for: while dragged, the one it would dock to.
    private var edge: Edge { model.dragging ? model.dragEdge : model.edge }
    private var items: [NotchLayout.PillItem] { NotchLayout.items(feed.providers, hovering: hovering) }

    // iOS-like motion.
    private let morph = Animation.spring(duration: 0.34, bounce: 0.16)
    private let follow = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.86)
    private let dock = Animation.spring(duration: 0.5, bounce: 0.24)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                pill(size)
                HoverCard(feed: feed, activity: activity, servers: servers, model: model, size: size,
                          onOpen: onOpen, onKill: onKill)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder private func pill(_ size: CGSize) -> some View {
        let h = NotchLayout.horizontal(edge)
        let detach: CGFloat = model.dragging ? 1 : 0
        let center = pillCenter(size)
        Group {
            if h {
                NotchRow(items: items, serverCount: servers.servers.count, detach: detach, levels: levels)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            } else {
                NotchColumn(items: items,
                            serverCount: servers.servers.count,
                            activity: hovering || model.dragging ? nil : activity.current,
                            right: edge == .right,
                            detach: detach,
                            levels: levels)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .animation(morph, value: activity.current)
        .animation(morph, value: items.map(\.layoutKey))
        .shadow(color: .black.opacity(model.dragging ? 0.45 : 0), radius: model.dragging ? 14 : 0,
                y: model.dragging ? 6 : 0)
        .scaleEffect(model.dragging ? 1.04 : 1)
        .position(center)
        .animation(follow, value: model.dragCenter)
        .animation(dock, value: model.dragEdge)
        .animation(dock, value: model.dragging)
        .animation(dock, value: model.edge)
    }

    /// Each provider's level, computed like its hover card (same pace).
    private var levels: [ProviderKind: UsageLevel] {
        var out: [ProviderKind: UsageLevel] = [:]
        for p in feed.providers {
            guard p.freshness == .live || p.freshness == .stale, let w = p.heroWindow else { continue }
            out[p.kind] = SessionPace(w, now: Date(),
                                      recent: w.span == .session ? activity.recentPace(p.kind) : nil).level
        }
        return out
    }

    /// Docked: the middle of the pill on its edge. Dragged: under the cursor,
    /// lifted a little off the edge it would dock to.
    private func pillCenter(_ size: CGSize) -> CGPoint {
        if model.dragging {
            let l = NotchLayout.lift
            var c = model.dragCenter
            switch model.dragEdge {
            case .left: c.x = max(c.x, NotchLayout.columnWidth / 2 + l)
            case .right: c.x = min(c.x, size.width - NotchLayout.columnWidth / 2 - l)
            case .bottom: c.y = min(c.y, size.height - NotchLayout.thickness(true) / 2 - l)
            }
            return c
        }
        let r = NotchLayout.pillRect(edge: model.edge, providers: feed.providers, hovering: hovering,
                                     frac: model.centerFrac, size: size)
        return CGPoint(x: r.midX, y: r.midY)
    }
}

/// The one hover card. It opens once (scale + fade from the pill side), then
/// follows the cursor between blocks: the card slides to the new block and
/// morphs its height while the old content slips out and the new slips in.
private struct HoverCard: View {
    @ObservedObject var feed: UsageFeed
    @ObservedObject var activity: ActivityTracker
    @ObservedObject var servers: ServerStore
    @ObservedObject var model: NotchModel
    let size: CGSize
    let onOpen: (LocalServer) -> Void
    let onKill: (LocalServer) -> Void

    @State private var shown: ActivePanel = .none
    @State private var open = false

    private var target: ActivePanel { model.dragging || model.active == .settings ? .none : model.active }
    private var panels: [ActivePanel] { feed.providers.map { .provider($0.kind) } + [.servers] }
    private var horizontal: Bool { NotchLayout.horizontal(model.edge) }

    var body: some View {
        let kind = shown == .none || shown == .settings ? (panels.first ?? .servers) : shown
        let r = rect(kind)
        let order = panels.firstIndex(of: kind) ?? 0
        ZStack(alignment: .top) {
            ForEach(panels, id: \.self) { k in
                let i = panels.firstIndex(of: k) ?? 0
                let on = k == kind
                let slip: CGFloat = on ? 0 : (i < order ? -14 : 14)
                content(k)
                    .environment(\.cardShown, on && open)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                        if model.tipH[k] != h { model.tipH[k] = h }
                    }
                    .opacity(on ? 1 : 0)
                    .blur(radius: on ? 0 : 5)
                    .offset(x: horizontal ? slip : 0, y: horizontal ? 0 : slip)
                    .allowsHitTesting(on)
            }
        }
        .frame(width: CardMetrics.width, height: max(1, r.height), alignment: .top)
        .animation(open ? .smooth(duration: 0.25) : nil, value: model.tipH[kind])
        .background(CardBackground(glow: glow(kind), leading: kind == .servers))
        .clipShape(RoundedRectangle(cornerRadius: CardMetrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CardMetrics.radius, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .scaleEffect(open ? 1 : 0.9, anchor: growAnchor)
        .opacity(open ? 1 : 0)
        .position(x: r.midX, y: r.midY)
        .animation(open ? .smooth(duration: 0.25) : nil, value: model.tipH[kind])
        .allowsHitTesting(open)
        .onChange(of: target) { _, new in apply(new) }
    }

    private func apply(_ new: ActivePanel) {
        if new == .none {
            withAnimation(.smooth(duration: 0.16)) { open = false }
        } else if !open {
            // First open: appear right at the block, no slide from the last spot.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { shown = new }
            DispatchQueue.main.async {
                withAnimation(.spring(duration: 0.32, bounce: 0.2)) { open = true }
            }
        } else {
            withAnimation(.spring(duration: 0.42, bounce: 0.16)) { shown = new }
        }
    }

    private func rect(_ k: ActivePanel) -> CGRect {
        NotchLayout.cardRect(active: k, edge: model.edge, providers: feed.providers,
                             hovering: model.active != .none && !model.dragging,
                             serverCount: servers.servers.count, measured: model.tipH[k],
                             grow: model.tipGrow[k] ?? 0,
                             frac: model.centerFrac, size: size)
    }

    private var growAnchor: UnitPoint {
        switch model.edge {
        case .left: return .leading
        case .right: return .trailing
        case .bottom: return .bottom
        }
    }

    @ViewBuilder private func content(_ k: ActivePanel) -> some View {
        switch k {
        case .provider(let kind):
            if let p = feed.providers.first(where: { $0.kind == kind }) {
                ProviderPanel(provider: p, recent: activity.recentPace(kind),
                              sampledFor: activity.sampledFor(kind), onGrow: { g in
                    if model.tipGrow[k] != g { model.tipGrow[k] = g }
                })
            }
        case .servers:
            ServersTooltipView(servers: Array(servers.servers.prefix(NotchLayout.maxRows)),
                               extra: max(0, servers.servers.count - NotchLayout.maxRows),
                               onOpen: onOpen, onKill: onKill)
        case .none, .settings:
            EmptyView()
        }
    }

    /// The soft light in the card's corner: the provider's color, turning
    /// yellow / red with the session level.
    private func glow(_ k: ActivePanel) -> Color {
        switch k {
        case .provider(let kind):
            guard let p = feed.providers.first(where: { $0.kind == kind }) else { return .clear }
            switch p.freshness {
            case .live, .stale:
                if let s = p.windows.first(where: { $0.span == .session }) ?? p.windows.first(where: { $0.span == .weekly }) {
                    let l = SessionPace(s, now: Date(),
                                        recent: s.span == .session ? activity.recentPace(kind) : nil).level
                    if l != .normal { return l.color }
                }
                return .white
            case .needsSetup, .unavailable: return .white.opacity(0.6)
            }
        case .servers: return .white
        case .none, .settings: return .clear
        }
    }
}

/// Black card with the soft light of Figma "Vector 601": a long blurred
/// white blob in the top corner (right for providers, left for servers),
/// tinted yellow / red when a provider's level calls for it.
private struct CardBackground: View {
    let glow: Color
    var leading = false
    var body: some View {
        ZStack(alignment: leading ? .topLeading : .topTrailing) {
            Color.black.opacity(0.9)
            Ellipse()
                .fill(glow)
                .frame(width: 108, height: 176)
                .rotationEffect(.degrees(leading ? 127 : 53))
                .blur(radius: 50)
                .opacity(0.26)
                .offset(x: leading ? -40 : 40, y: -80)
        }
        .animation(.smooth(duration: 0.4), value: glow)
    }
}
