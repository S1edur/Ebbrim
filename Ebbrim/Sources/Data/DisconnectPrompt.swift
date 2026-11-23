import Foundation

/// Text of the confirmation shown before a source is disconnected. Ebbrim
/// holds no login for any source, so disconnecting only stops reading and
/// forgets what Ebbrim kept; the user's own logins are never touched.
enum DisconnectPrompt {
    struct Text: Equatable { let title: String; let body: String }

    static func text(for action: FeedAction) -> Text? {
        switch action {
        case .setClaude(false):
            return Text(title: "Disconnect Claude?", body: """
            Ebbrim will stop reading Claude Desktop's cache and forget the latest numbers.
            Your Claude login is not affected: Ebbrim never had it. \
            Reconnect any time with one click, no sign-in needed.
            """)
        case .setCodex(false):
            return Text(title: "Disconnect Codex?", body: """
            Ebbrim will stop asking Codex's helper for limits and forget the latest numbers.
            Your Codex login is not affected: Ebbrim never saw it. \
            Reconnect any time with one click, no sign-in needed.
            """)
        case .setTerminal(false):
            return Text(title: "Disconnect Claude Code in Terminal?", body: """
            Ebbrim will remove its line from ~/.claude/settings.json, put back your previous statusLine \
            (if you had one), and delete its script copy and saved limits.
            Reconnect any time with one click.
            """)
        default:
            return nil
        }
    }
}
