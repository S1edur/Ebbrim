import Foundation

/// Text of the "About Access" panel: what Ebbrim reads, and the live state of
/// each source.
enum AccessText {
    static let title = "What Ebbrim reads"

    static func body(providers: [ProviderUsage], codexEnabled: Bool, terminalConnected: Bool, now: Date) -> String {
        let claude = providers.first { $0.kind == .claude }
        let codex = providers.first { $0.kind == .codex }
        return """
        Claude: the usage record Claude Desktop keeps on this Mac — \(state(claude, now)).
        Codex: asks Codex's built-in helper, which talks to OpenAI with Codex's own login. \
        Ebbrim never sees that login — \(codexEnabled ? state(codex, now) : "off").
        Claude Code in Terminal: \(terminalConnected ? "connected" : "not connected").

        • No tokens, Keychain or passwords.
        • Ebbrim itself never goes online.
        • Your data stays on this Mac.
        """
    }

    private static func state(_ p: ProviderUsage?, _ now: Date) -> String {
        guard let p else { return "no data yet" }
        if let at = p.capturedAt {
            let mins = Int(now.timeIntervalSince(at) / 60)
            return mins < 1 ? "just now" : "updated \(mins) min ago"
        }
        switch p.freshness {
        case .needsSetup(let hint): return hint
        case .unavailable(let reason): return reason
        default: return "no data yet"
        }
    }
}
