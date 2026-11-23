import SwiftUI

// Shared pieces of the onboarding and Settings windows: one look for every
// source (what it reads, its state, the one control that changes it).

enum SetupStyle {
    static let accent = Color.white                 // onboarding / Settings: white, no orange
    static let bg = Color(white: 0.055)
    static let row = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.07)
    static let title = Font.custom("Inter", size: 30).weight(.semibold)
    static let rowTitle = Font.custom("Inter", size: 13.5).weight(.medium)
    static let rowBody = Font.custom("Inter", size: 11.5)
}

/// A source the app can read, as both windows show it.
enum SetupSource: CaseIterable, Identifiable {
    case claudeDesktop, terminal, codex, servers
    var id: Self { self }

    var title: String {
        switch self {
        case .claudeDesktop: return "Claude"
        case .terminal: return "Claude Code in Terminal"
        case .codex: return "Codex"
        case .servers: return "Local servers"
        }
    }
    var body: String {
        switch self {
        case .claudeDesktop: return "Reads the usage record Claude Desktop keeps on this Mac. Connect, and it starts reading."
        case .terminal: return "Exact limits from Claude Code via a statusLine in ~/.claude/settings.json. Your own statusLine keeps working."
        case .codex: return "Asks Codex's own helper for its limits. Codex signs in by itself; Ebbrim never sees that sign-in."
        case .servers: return "Finds dev servers listening on localhost, so you can open or stop them."
        }
    }
}

/// The one line under a source worth reading: only when something needs
/// doing (not set up, can't read, waiting for its first data). A working or
/// switched-off source says nothing; its button already tells.
enum SourceNote {
    static func of(_ s: SetupSource, feed: UsageFeed) -> (text: String, problem: Bool)? {
        func provider(_ k: ProviderKind) -> ProviderUsage? { feed.providers.first { $0.kind == k } }
        func note(_ f: Freshness) -> (String, Bool)? {
            switch f {
            case .live, .stale: return nil
            case .needsSetup(let hint): return (hint, false)
            case .unavailable(let reason): return (reason, true)
            }
        }
        switch s {
        case .claudeDesktop:
            guard feed.settings.claudeEnabled else { return nil }
            guard let p = provider(.claude) else { return ("Waiting for Claude Desktop. Open it once.", false) }
            return note(p.freshness)
        case .codex:
            guard feed.settings.codexEnabled else { return nil }
            guard let p = provider(.codex) else { return ("Looking for Codex…", false) }
            return note(p.freshness)
        case .terminal, .servers:
            return nil
        }
    }

    /// Claude Desktop is feeding Claude right now.
    static func desktopWorks(_ feed: UsageFeed) -> Bool {
        guard feed.settings.claudeEnabled, let p = feed.providers.first(where: { $0.kind == .claude }) else { return false }
        return p.freshness == .live || p.freshness == .stale
    }
}

/// A data source in "Sources": icon, title, what it reads, a note only when
/// something needs doing, and one button: Connect or Disconnect.
struct SourceRow: View {
    let source: SetupSource
    @ObservedObject var feed: UsageFeed
    /// An add-on of the row above (Terminal under Claude): indented, smaller,
    /// tagged "Optional", so it doesn't read as a second Claude.
    var nested = false

    /// Terminal is offered only while Claude is on and Claude Desktop isn't
    /// already feeding it, or when it's connected (so it can be disconnected).
    static func showsTerminal(feed: UsageFeed) -> Bool {
        if feed.settings.terminalConnected { return true }
        return feed.settings.claudeEnabled && !SourceNote.desktopWorks(feed)
    }

    var body: some View {
        HStack(alignment: .center, spacing: nested ? 10 : 14) {
            SourceIcon(source: source, size: nested ? 28 : 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.title).font(nested ? SetupStyle.rowBody.weight(.medium) : SetupStyle.rowTitle)
                        .foregroundStyle(.white)
                    if nested {
                        Text("Optional").font(CardType.tag).tracking(0.2)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Text(source.body).font(SetupStyle.rowBody).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if let n = SourceNote.of(source, feed: feed) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if n.problem {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                                .foregroundStyle(Theme.yellow)
                        }
                        Text(n.text).font(SetupStyle.rowBody.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            button
        }
        .padding(.vertical, nested ? 10 : 14)
        .padding(.leading, nested ? 56 : 0)
        .padding(.top, nested ? -8 : 0)
    }

    @ViewBuilder private var button: some View {
        switch source {
        case .claudeDesktop: connect(feed.settings.claudeEnabled) { feed.perform(.setClaude($0)) }
        case .codex: connect(feed.settings.codexEnabled) { feed.perform(.setCodex($0)) }
        case .terminal: connect(feed.settings.terminalConnected) { feed.perform(.setTerminal($0)) }
        case .servers: EmptyView()
        }
    }

    private func connect(_ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        PillButton(title: on ? "Disconnect" : "Connect", prominent: !on) { set(!on) }
    }
}

/// "Appearance": what the notch shows. One switch per item, nothing else.
/// Claude / Codex only hide from the notch (they keep being read); Local
/// servers stops scanning too. A disconnected source can't be shown.
struct AppearanceRow: View {
    let source: SetupSource
    @ObservedObject var feed: UsageFeed
    @ObservedObject var model: NotchModel

    var body: some View {
        let available = isAvailable
        HStack(spacing: 12) {
            SourceIcon(source: source, size: 28)
            Text(source.title).font(SetupStyle.rowTitle).foregroundStyle(.white)
            Spacer(minLength: 12)
            SetupToggle(isOn: available && isOn) { set($0) }
                .disabled(!available)
                .opacity(available ? 1 : 0.35)
        }
        .padding(.vertical, 11)
    }

    private var isAvailable: Bool {
        switch source {
        case .claudeDesktop: return feed.settings.claudeEnabled
        case .codex: return feed.settings.codexEnabled
        default: return true
        }
    }
    private var isOn: Bool {
        switch source {
        case .claudeDesktop: return !model.hiddenKinds.contains(.claude)
        case .codex: return !model.hiddenKinds.contains(.codex)
        case .servers: return feed.settings.serversEnabled
        case .terminal: return false
        }
    }
    private func set(_ on: Bool) {
        switch source {
        case .claudeDesktop: if on { model.hiddenKinds.remove(.claude) } else { model.hiddenKinds.insert(.claude) }
        case .codex: if on { model.hiddenKinds.remove(.codex) } else { model.hiddenKinds.insert(.codex) }
        case .servers: feed.perform(.setServers(on))
        case .terminal: break
        }
    }
}

struct SourceIcon: View {
    let source: SetupSource
    var size: CGFloat = 42
    var body: some View {
        Group {
            switch source {
            case .claudeDesktop: ProviderLogo(kind: .claude, size: size * 0.52, color: Theme.claudeOrange)
            case .terminal:
                Image(systemName: "terminal.fill").font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(.white)
            case .codex: ProviderLogo(kind: .codex, size: size * 0.52, color: .white)
            case .servers: Image(nsImage: Marks.database).resizable().frame(width: size * 0.48, height: size * 0.48)
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }
}

struct PillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.custom("Inter", size: 12.5).weight(.semibold))
                .foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 16).frame(height: 32)
                .background(prominent ? Color.white.opacity(hover ? 1 : 0.92) : Color.white.opacity(hover ? 0.16 : 0.1),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct TextButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.custom("Inter", size: 11.5).weight(.medium))
                .foregroundStyle(.white.opacity(hover ? 0.9 : 0.55))
                .underline(hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// The green switch of the references. It shows the real state it's given
/// and only asks for a change; the data layer decides.
struct SetupToggle: View {
    let isOn: Bool
    let onChange: (Bool) -> Void
    var body: some View {
        Button { onChange(!isOn) } label: {
            Capsule()
                .fill(isOn ? Theme.green : Color.white.opacity(0.16))
                .frame(width: 42, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
                .animation(.spring(duration: 0.3, bounce: 0.25), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// Left / Right / Bottom tiles with a tiny screen showing where the notch goes.
struct EdgePicker: View {
    let edge: Edge
    let onEdge: (Edge) -> Void
    var body: some View {
        HStack(spacing: 10) {
            tile(.left, "Left"); tile(.right, "Right"); tile(.bottom, "Bottom")
        }
    }

    private func tile(_ e: Edge, _ title: String) -> some View {
        let on = edge == e
        return Button { onEdge(e) } label: {
            VStack(spacing: 8) {
                ZStack(alignment: e == .left ? .leading : e == .right ? .trailing : .bottom) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    Capsule().fill(on ? SetupStyle.accent : Color.white.opacity(0.45))
                        .frame(width: e == .bottom ? 22 : 4, height: e == .bottom ? 4 : 16)
                        .padding(3)
                }
                .frame(width: 64, height: 40)
                Text(title).font(.custom("Inter", size: 12).weight(.medium))
                    .foregroundStyle(on ? .white : .white.opacity(0.6))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.white.opacity(on ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? SetupStyle.accent.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Local servers, full size like Open at Login: what it shows and its switch
/// (feed.perform(.setServers): off stops the scanning too).
struct ServersRow: View {
    @ObservedObject var feed: UsageFeed
    var body: some View {
        HStack(spacing: 14) {
            SourceIcon(source: .servers)
            VStack(alignment: .leading, spacing: 3) {
                Text("Local servers").font(SetupStyle.rowTitle).foregroundStyle(.white)
                Text("Shows the dev servers running on this Mac — project, port, CPU and memory — so you can open or stop them from the notch.")
                    .font(SetupStyle.rowBody).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            SetupToggle(isOn: feed.settings.serversEnabled) { feed.perform(.setServers($0)) }
        }
        .padding(.vertical, 14)
    }
}

/// Last row of General: remove Ebbrim and everything it left. The data layer
/// asks first (and moves the app to the Trash), so no confirmation here.
struct UninstallRow: View {
    @ObservedObject var feed: UsageFeed
    @State private var hover = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.red.opacity(0.9))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Uninstall Ebbrim").font(SetupStyle.rowTitle).foregroundStyle(.white)
                Text("Removes the app, its settings and data, and gives your Claude Code statusLine back.")
                    .font(SetupStyle.rowBody).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button { feed.perform(.uninstall) } label: {
                Text("Uninstall…").font(.custom("Inter", size: 12.5).weight(.semibold))
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(Theme.red.opacity(hover ? 0.2 : 0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
        .padding(.vertical, 14)
    }
}

/// "Open at Login" with the toggle; if macOS refuses, it says so.
struct LoginRow: View {
    @ObservedObject var feed: UsageFeed
    @State private var asked: Bool?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "power").font(.system(size: 17, weight: .semibold)).foregroundStyle(SetupStyle.accent)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Open at Login").font(SetupStyle.rowTitle).foregroundStyle(.white)
                Text("Keep the notch there every time you start your Mac.")
                    .font(SetupStyle.rowBody).foregroundStyle(.white.opacity(0.55))
                if let a = asked, a != feed.settings.launchAtLogin {
                    Text("macOS didn't allow it. Check System Settings › General › Login Items.")
                        .font(SetupStyle.rowBody).foregroundStyle(Theme.yellow.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            SetupToggle(isOn: feed.settings.launchAtLogin) { on in
                feed.perform(.setLaunchAtLogin(on))
                // The data layer answers right away; give it a beat before judging.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { asked = on }
            }
        }
        .padding(.vertical, 14)
        .onChange(of: feed.settings.launchAtLogin) { _, v in if v == asked { asked = nil } }
    }
}

/// The thin line between rows.
struct Hairline: View {
    var body: some View { Rectangle().fill(SetupStyle.hairline).frame(height: 0.5) }
}
