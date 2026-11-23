import SwiftUI

/// First-run walkthrough (after the Raycast / Dia onboarding references):
/// tag + big title + one line on the left, the step itself on the right,
/// page dots and Back / Continue at the bottom. Five steps:
/// welcome → connect sources → privacy → preferences → ready.
struct OnboardingView: View {
    @ObservedObject var feed: UsageFeed
    @ObservedObject var model: NotchModel
    let onEdge: (Edge) -> Void
    let onFinish: () -> Void

    @State private var step = 0
    @State private var forward = true
    private let count = 5

    var body: some View {
        ZStack(alignment: .bottom) {
            SetupStyle.bg
            if step == 0 {
                // Welcome: the product face-first. A desktop on the right with
                // the real notch cycling through its states; the pitch on the left.
                HeroScene()
                    .frame(width: 500)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.opacity)
                welcome
                    .frame(width: 340, alignment: .leading)
                    // Clear of the window buttons: the tag sits 44 pt below the title bar.
                    .padding(.leading, 48).padding(.top, 28 + 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(slide)
            } else {
                HStack(alignment: .center, spacing: 40) {
                    intro
                        .frame(width: 290, alignment: .leading)
                        .id("intro\(step)")
                        .transition(slide)
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("content\(step)")
                        .transition(slide)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 64)
                .frame(maxHeight: .infinity)
            }
            if step > 0 { footer }          // the welcome is a page of its own, not slide 1
        }
        .frame(width: 860, height: 540)
        .preferredColorScheme(.dark)
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)),
                    removal: .opacity.combined(with: .offset(x: forward ? -24 : 24)))
    }

    private func go(_ to: Int) {
        forward = to > step
        withAnimation(.spring(duration: 0.45, bounce: 0.12)) { step = max(0, min(count - 1, to)) }
    }

    // MARK: left column

    /// What Ebbrim is, in one line, and what it does, as a plain list.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            EbbrimLogo(height: 22).padding(.bottom, 6)
            Text("Know what's left,\nbefore it runs out").font(SetupStyle.title).tracking(-0.6)
                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            Text("A small tracker at the edge of your screen: how much of Claude and Codex you have, when it runs out, and which dev servers are running.")
                .font(.custom("Inter", size: 14)).foregroundStyle(.white.opacity(0.6))
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                feature("gauge.with.dots.needle.50percent", "What's left of each session and the week")
                feature("timer", "When it runs out at your pace")
                feature("bell.badge", "A heads-up only when a session is at risk")
                feature("server.rack", "Your dev servers, open or stop them")
            }
            .padding(.top, 6)
            PrimaryButton(title: "Get started") { go(1) }
                .padding(.top, 14)
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.08), in: Circle())
            Text(text).font(.custom("Inter", size: 13.5).weight(.medium)).foregroundStyle(.white.opacity(0.88))
        }
    }

    private var intro: some View {
        let (tag, title, line) = copy
        return VStack(alignment: .leading, spacing: 14) {
            Text(tag)
                .font(.custom("Inter", size: 12).weight(.semibold))
                .foregroundStyle(SetupStyle.accent)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(SetupStyle.accent.opacity(0.14), in: Capsule())
            Text(title).font(SetupStyle.title).tracking(-0.6).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(line).font(.custom("Inter", size: 14)).foregroundStyle(.white.opacity(0.6))
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var copy: (String, String, String) {
        switch step {
        case 0: return ("Ebbrim", "Your AI limits,\nat the edge\nof the screen",
                        "See what's left of your Claude and Codex sessions at a glance. Hover for the details.")
        case 1: return ("Sources", "Connect\nyour tools",
                        "Ebbrim reads the usage your apps already keep on this Mac. Turn on what you use.")
        case 2: return ("Privacy", "It all stays\non your Mac",
                        "No sign-in, no tokens, no network. You can turn any source off later in Settings.")
        case 3: return ("Preferences", "Make it\nyours",
                        "Pick an edge and decide if the notch starts with your Mac. You can drag it later too.")
        default: return ("Ready", "You're\nall set",
                         "Three things to know, and you're good to go.")
        }
    }

    // MARK: right column

    @ViewBuilder private var content: some View {
        switch step {
        case 0: EmptyView()
        case 1:
            VStack(spacing: 0) {
                SourceRow(source: .claudeDesktop, feed: feed)
                if SourceRow.showsTerminal(feed: feed) {
                    SourceRow(source: .terminal, feed: feed, nested: true)
                }
                Hairline()
                SourceRow(source: .codex, feed: feed)
            }
        case 2:
            VStack(spacing: 0) {
                Fact(icon: "key.slash", title: "No tokens or passwords",
                     detail: "Nothing from your Keychain, no sign-in to any account.")
                Hairline()
                Fact(icon: "wifi.slash", title: "Never goes online",
                     detail: "Ebbrim itself makes no network requests.")
                Hairline()
                Fact(icon: "internaldrive", title: "Data stays on this Mac",
                     detail: "Only usage numbers, read from files your apps already write.")
                Hairline()
                Fact(icon: "switch.2", title: "You stay in control",
                     detail: "Disconnect Claude Code or turn Codex off at any time in Settings.")
            }
        case 3:
            VStack(alignment: .leading, spacing: 4) {
                LoginRow(feed: feed)
                Hairline()
                ServersRow(feed: feed)
                Hairline()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Where the notch sits").font(SetupStyle.rowTitle).foregroundStyle(.white)
                    EdgePicker(edge: model.edge, onEdge: onEdge)
                }
            }
        default:
            VStack(spacing: 0) {
                // Skipped Connect: say where it went, so an empty notch isn't a mystery.
                if !feed.settings.claudeEnabled && !feed.settings.codexEnabled {
                    Fact(icon: "plus.circle", title: "Nothing connected yet",
                         detail: "The notch shows + Claude and + Codex. Click one to connect it.")
                    Hairline()
                }
                Fact(icon: "cursorarrow.motionlines", title: "Hover a block",
                     detail: "Each provider and your servers open their own card.")
                Hairline()
                Fact(icon: "hand.draw", title: "Drag the notch",
                     detail: "Pull it off the edge and drop it on the left, right or bottom.")
                Hairline()
                Fact(icon: "gearshape", title: "Settings are one click away",
                     detail: "Hover the notch and click the gear at its end.")
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 18) {
            Button { go(step - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.leftArrow, modifiers: [])

            HStack(spacing: 5) {
                ForEach(1..<count, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? SetupStyle.accent : Color.white.opacity(0.18))
                        .frame(width: i == step ? 28 : 12, height: 4)
                        .shadow(color: i == step ? SetupStyle.accent.opacity(0.7) : .clear, radius: 5)
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: step)

            Spacer()

            PrimaryButton(title: step == count - 1 ? "Start using Ebbrim" : "Continue") {
                step == count - 1 ? onFinish() : go(step + 1)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }
}

/// The light main button (after Dia's "Choose File… ↵"), Return triggers it.
private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(.custom("Inter", size: 14).weight(.semibold))
                Image(systemName: "return").font(.system(size: 10, weight: .bold)).opacity(0.6)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 20).frame(height: 40)
            .background(Color.white.opacity(hover ? 1 : 0.9), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .keyboardShortcut(.defaultAction)
    }
}

/// One line of reassurance or a tip: icon, title, one sentence.
private struct Fact: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SetupStyle.rowTitle).foregroundStyle(.white)
                Text(detail).font(SetupStyle.rowBody).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

/// The picture's left boundary: a lazy wave from top to bottom (fixed, so it
/// doesn't jump between launches), filled to the right.
private struct OrganicEdge: Shape {
    /// Width on the left that lies outside the scene; fractions start after it.
    var lead: CGFloat = 0
    func path(in r: CGRect) -> Path {
        let w = r.width - lead, h = r.height
        func x(_ f: CGFloat) -> CGFloat { r.minX + lead + w * f }
        func y(_ f: CGFloat) -> CGFloat { r.minY + h * f }
        var p = Path()
        p.move(to: CGPoint(x: x(0.46), y: y(-0.3)))
        p.addCurve(to: CGPoint(x: x(0.30), y: y(0.34)),
                   control1: CGPoint(x: x(0.40), y: y(0.06)), control2: CGPoint(x: x(0.24), y: y(0.20)))
        p.addCurve(to: CGPoint(x: x(0.43), y: y(0.66)),
                   control1: CGPoint(x: x(0.36), y: y(0.48)), control2: CGPoint(x: x(0.50), y: y(0.54)))
        p.addCurve(to: CGPoint(x: x(0.24), y: y(1.3)),
                   control1: CGPoint(x: x(0.36), y: y(0.80)), control2: CGPoint(x: x(0.20), y: y(0.92)))
        p.addLine(to: CGPoint(x: r.maxX + 240, y: y(1.3)))
        p.addLine(to: CGPoint(x: r.maxX + 240, y: y(-0.3)))
        p.closeSubpath()
        return p
    }
}

/// Welcome visual (after the Dia onboarding): a desktop with a painting
/// behind it — calm negative space — and the real notch on its right edge,
/// opening one state after another: Claude's card, Codex's card, the local
/// servers, then the at-risk island. Sample numbers, never the user's.
private struct HeroScene: View {
    @State private var phase = 0
    /// Sample numbers matching what each plan really shows: Claude on a plan
    /// with a 5-hour session (no plan badge, the source doesn't name it),
    /// Codex with its plan.
    private let sample: [ProviderUsage] = {
        let now = Date()
        return [
            ProviderUsage(kind: .claude, name: "Claude",
                          windows: [LimitWindow(id: "claude.session", span: .session, usedPercent: 18,
                                                resetsAt: now.addingTimeInterval(2 * 3600 + 840)),
                                    LimitWindow(id: "claude.weekly", span: .weekly, usedPercent: 41,
                                                resetsAt: now.addingTimeInterval(3 * 86400))],
                          capturedAt: now, freshness: .live, sourceLabel: "Claude Desktop"),
            ProviderUsage(kind: .codex, name: "Codex",
                          windows: [LimitWindow(id: "codex.session", span: .session, usedPercent: 63,
                                                resetsAt: now.addingTimeInterval(3600)),
                                    LimitWindow(id: "codex.weekly", span: .weekly, usedPercent: 12,
                                                resetsAt: now.addingTimeInterval(5 * 86400))],
                          capturedAt: now, freshness: .live, sourceLabel: "Codex", plan: "Plus"),
        ]
    }()
    private let servers = [
        LocalServer(pid: 1, port: 5173, kind: "Vite", project: "landing", cpu: 3, memMB: 210),
        LocalServer(pid: 2, port: 3000, kind: "Next", project: "dashboard", cpu: 9, memMB: 356),
        LocalServer(pid: 3, port: 8080, kind: "Node", project: "api", cpu: 1, memMB: 96),
    ]
    private static let bleed: CGFloat = 220
    private static let painting: NSImage? = Bundle.main.url(forResource: "onboarding-sea", withExtension: "jpg")
        .flatMap { NSImage(contentsOf: $0) }

    private var items: [NotchLayout.PillItem] { sample.map(NotchLayout.PillItem.provider) + [.servers] }
    private var alert: ActivityTracker.Activity {
        ActivityTracker.Activity(kind: .claude, severity: .risk, left: 40,
                                 runsOutAt: Date().addingTimeInterval(110 * 60),
                                 resetsAt: Date().addingTimeInterval(134 * 60))
    }
    /// Where each state's card centers, from the pill's middle.
    private var cardOffset: CGFloat {
        let L = NotchLayout.self, its = items
        let mid = L.columnH(its) / 2
        let panel: ActivePanel = phase == 0 ? .provider(.claude) : phase == 1 ? .provider(.codex) : .servers
        return (L.anchor(panel, its, false) ?? mid) - mid
    }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .trailing) { scene }
                .frame(width: g.size.width, height: g.size.height, alignment: .trailing)
                // The painting bleeds past the scene's left side, so its blurred
                // edge has room to fade out instead of being cut at the frame.
                .background(alignment: .trailing) {
                    background(CGSize(width: g.size.width + Self.bleed, height: g.size.height), lead: Self.bleed)
                }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.8))
                withAnimation(.spring(duration: 0.5, bounce: 0.15)) { phase = (phase + 1) % 4 }
            }
        }
    }

    private var scene: some View {
            HStack(alignment: .center, spacing: CardMetrics.gap) {
                ZStack {
                    if phase < 3 {
                        card
                            .id(phase)
                            // The old card leaves fast, so two never overlap.
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .trailing))
                                    .animation(.spring(duration: 0.45, bounce: 0.15).delay(0.12)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))))
                    }
                }
                .offset(y: cardOffset)
                .frame(width: CardMetrics.width * 0.86, alignment: .trailing)
                NotchColumn(items: items, serverCount: servers.count,
                            activity: phase == 3 ? alert : nil, right: true)
                    .frame(width: NotchLayout.columnWidth)
            }
    }

    @ViewBuilder private var card: some View {
        Group {
            switch phase {
            case 0: ProviderPanel(provider: sample[0])
            case 1: ProviderPanel(provider: sample[1])
            default: ServersTooltipView(servers: servers, onOpen: { _ in }, onKill: { _ in })
            }
        }
        .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: CardMetrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CardMetrics.radius, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .scaleEffect(0.86, anchor: .trailing)
        .frame(width: CardMetrics.width * 0.86, alignment: .trailing)
    }

    private func background(_ size: CGSize, lead: CGFloat) -> some View {
        // Gradient stops in the scene's own fractions, shifted past the bleed.
        func at(_ f: CGFloat) -> CGFloat { (lead + (size.width - lead) * f) / size.width }
        return ZStack {
            if let img = Self.painting {
                // Soft edge like the reference: a heavily blurred copy carries
                // the color out to the left, the sharp one fades in over it.
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .blur(radius: 36, opaque: true)
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: at(0.18)), .init(color: .black.opacity(0.6), location: at(0.42)),
                                                 .init(color: .black, location: at(0.62))],
                                         startPoint: .leading, endPoint: .trailing))
            } else {
                LinearGradient(colors: [Color(red: 0.32, green: 0.4, blue: 0.44), Color(red: 0.1, green: 0.16, blue: 0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Color.black.opacity(0.18)
        }
        .frame(width: size.width, height: size.height)
        // Melt into whatever is under it on the left (no seam), like the reference.
        // An organic edge instead of a straight fade: a wavy boundary, blurred soft.
        .mask(OrganicEdge(lead: lead).fill(.black).blur(radius: 110))
    }
}
