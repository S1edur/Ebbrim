import Foundation
import Combine

// MARK: - The contract between the data layer and the UI
//
// The UI reads ONLY these types. The data layer (sources, merging, staleness)
// writes `UsageFeed.providers` and nothing else. Changing anything in this file
// is a contract change: agree it in both branches (data and UI) first.

/// Which product a reading belongs to. New providers are added here.
enum ProviderKind: String, CaseIterable, Identifiable {
    case claude
    case codex
    var id: String { rawValue }
}

/// One limit window, e.g. the 5-hour session or the weekly limit.
struct LimitWindow: Identifiable, Equatable {
    enum Span: Equatable {
        case session                     // Claude 5-hour, Codex primary
        case weekly                      // Claude 7-day, Codex secondary
        case other(String)               // anything a provider adds later
    }

    var id: String                       // stable per provider, e.g. "claude.session"
    var span: Span
    var usedPercent: Double              // 0...100; may exceed 100 if a source says so
    var resetsAt: Date?                  // nil when the source doesn't say
}

/// How far the numbers can be trusted right now. The UI must show this
/// honestly: never present a `.stale` reading as live.
enum Freshness: Equatable {
    case live                            // newest reading is recent
    case stale                           // shown with its age, dimmed
    case needsSetup(hint: String)        // nothing to read yet, and what to do
    case unavailable(reason: String)     // source exists but can't be read
}

/// Everything the UI needs about one provider.
struct ProviderUsage: Identifiable, Equatable {
    var kind: ProviderKind
    var name: String                     // display name, "Claude", "Codex"
    var windows: [LimitWindow]           // session first, then weekly, then others
    var capturedAt: Date?                // when the numbers were true
    var freshness: Freshness
    var sourceLabel: String              // e.g. "Claude Desktop", "Claude Code CLI"
    var plan: String? = nil              // as the product names it: "Pro", "Max 5x", "Plus"; nil if unknown

    var id: ProviderKind { kind }

    /// The headline number for a ring: the session window, else the first.
    var headlineUsed: Double? {
        (windows.first { $0.span == .session } ?? windows.first)?.usedPercent
    }
}

/// User switches the data layer owns. The UI shows them (Settings window,
/// menu) and asks for changes with `UsageFeed.perform`; the data layer applies
/// the change and writes the new state back here.
struct FeedSettings: Equatable {
    var claudeEnabled = true             // read Claude sources and show Claude
    var codexEnabled = true              // poll Codex's helper and show Codex
    var terminalConnected = false        // Claude Code statusLine source installed
    var launchAtLogin = false            // login item registered
    var serversEnabled = true            // scan for local dev servers
}

/// A change the UI asks the data layer to make. `setTerminal(true)` may show a
/// confirmation first (it edits ~/.claude/settings.json); read the result from
/// `UsageFeed.settings`, not from the request.
enum FeedAction: Equatable {
    case setClaude(Bool)
    case setCodex(Bool)
    case setTerminal(Bool)
    case setLaunchAtLogin(Bool)
    case setServers(Bool)
    case uninstall                       // asks first; removes Ebbrim and every trace it left
}

/// The one observable object the UI binds to.
final class UsageFeed: ObservableObject {
    @Published var providers: [ProviderUsage] = []
    @Published var settings = FeedSettings()

    /// Ask the data layer to re-read its sources now (menu "Refresh").
    var onRefreshRequest: (() -> Void)?
    func requestRefresh() { onRefreshRequest?() }

    /// Ask the data layer to change a switch (Settings window / menu).
    var onAction: ((FeedAction) -> Void)?
    func perform(_ action: FeedAction) { onAction?(action) }

    /// True when the app was launched for UI work with fake data:
    /// `EBBRIM_MOCK=1 ./Ebbrim.app/Contents/MacOS/Ebbrim`
    /// or `open Ebbrim.app --env EBBRIM_MOCK=1`.
    static var isMock: Bool {
        ProcessInfo.processInfo.environment["EBBRIM_MOCK"] == "1"
    }

    /// Mock a brand-new user: nothing connected until Connect is pressed:
    /// `EBBRIM_MOCK=1 EBBRIM_MOCK_FRESH=1 …`.
    static var isMockFresh: Bool {
        ProcessInfo.processInfo.environment["EBBRIM_MOCK_FRESH"] == "1"
    }

    /// Mock a Max 20x account (weekly limit only, no 5-hour session):
    /// `EBBRIM_MOCK=1 EBBRIM_MOCK_CLAUDE=20x …`.
    static var isMockClaude20x: Bool {
        ProcessInfo.processInfo.environment["EBBRIM_MOCK_CLAUDE"] == "20x"
    }
}

// MARK: - Fake data for UI work

extension UsageFeed {
    /// A feed with every state the UI has to handle, cycling every few seconds
    /// so live updates and state changes can be seen without real sources.
    static func mock(fresh: Bool = isMockFresh) -> UsageFeed {
        let feed = UsageFeed()
        if fresh { feed.settings = FeedSettings(claudeEnabled: false, codexEnabled: false, serversEnabled: false) }
        var step = 0
        // Like the real data layer: a disconnected provider is not in `providers`.
        let publish = { [weak feed] in
            guard let feed else { return }
            feed.providers = mockFrame(step).filter {
                $0.kind == .claude ? feed.settings.claudeEnabled : feed.settings.codexEnabled
            }
        }
        feed.onAction = { [weak feed] action in       // fake data layer: apply at once
            switch action {
            case .setClaude(let on): feed?.settings.claudeEnabled = on
            case .setCodex(let on): feed?.settings.codexEnabled = on
            case .setServers(let on): feed?.settings.serversEnabled = on
            case .uninstall: break
            case .setTerminal(let on): feed?.settings.terminalConnected = on
            case .setLaunchAtLogin(let on): feed?.settings.launchAtLogin = on
            }
            publish()
        }
        publish()
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            step += 1
            publish()
        }
        return feed
    }

    static func mockFrame(_ step: Int, claude20x: Bool = isMockClaude20x) -> [ProviderUsage] {
        let now = Date()
        let claudeUsed = Double((18 + step * 7) % 105)       // walks through green → red → >100
        let session = LimitWindow(id: "claude.session", span: .session,
                                  usedPercent: claudeUsed, resetsAt: now.addingTimeInterval(2 * 3600 + 900))
        let weekly = LimitWindow(id: "claude.weekly", span: .weekly,
                                 usedPercent: claude20x ? claudeUsed : 41, resetsAt: now.addingTimeInterval(3 * 86400))
        let claude = ProviderUsage(
            kind: .claude, name: "Claude",
            windows: claude20x ? [weekly] : [session, weekly],
            capturedAt: now.addingTimeInterval(step % 6 == 5 ? -9 * 60 : -20),
            freshness: step % 6 == 5 ? .stale : .live,
            sourceLabel: "Claude Desktop", plan: claude20x ? "Max 20x" : nil)

        let codexStates: [ProviderUsage] = [
            ProviderUsage(kind: .codex, name: "Codex",
                          windows: [
                            LimitWindow(id: "codex.session", span: .session,
                                        usedPercent: 63, resetsAt: now.addingTimeInterval(3600)),
                            LimitWindow(id: "codex.weekly", span: .weekly,
                                        usedPercent: 12, resetsAt: now.addingTimeInterval(5 * 86400)),
                          ],
                          capturedAt: now.addingTimeInterval(-60), freshness: .live,
                          sourceLabel: "Codex", plan: "Plus"),
            ProviderUsage(kind: .codex, name: "Codex", windows: [], capturedAt: nil,
                          freshness: .needsSetup(hint: "Open Codex once to start"),
                          sourceLabel: "Codex"),
            ProviderUsage(kind: .codex, name: "Codex", windows: [], capturedAt: nil,
                          freshness: .unavailable(reason: "Usage data format changed"),
                          sourceLabel: "Codex"),
        ]
        return [claude, codexStates[(step / 3) % codexStates.count]]
    }
}
