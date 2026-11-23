import Foundation

func accessTextTests() {
    let now = utc("2026-11-22T21:00:00Z")
    let claude = ProviderUsage(kind: .claude, name: "Claude", windows: [], capturedAt: now.addingTimeInterval(-180),
                               freshness: .live, sourceLabel: "Claude Desktop")
    let codexSetup = ProviderUsage(kind: .codex, name: "Codex", windows: [], capturedAt: nil,
                                   freshness: .needsSetup(hint: "Open Codex and sign in"), sourceLabel: "Codex")
    run("testAccessTextStates") {
        let t = AccessText.body(providers: [claude, codexSetup], codexEnabled: true, terminalConnected: false, now: now)
        expect(t.contains("the usage record Claude Desktop keeps on this Mac — updated 3 min ago."), t)
        expect(t.contains("Ebbrim never sees that login — Open Codex and sign in."), t)
        expect(t.contains("Claude Code in Terminal: not connected."), t)
        expect(t.contains("• No tokens, Keychain or passwords.") && t.contains("• Ebbrim itself never goes online."), t)
    }
    run("testAccessTextCodexOffAndJustNow") {
        let fresh = ProviderUsage(kind: .claude, name: "Claude", windows: [], capturedAt: now.addingTimeInterval(-20),
                                  freshness: .live, sourceLabel: "Claude Desktop")
        let t = AccessText.body(providers: [fresh], codexEnabled: false, terminalConnected: true, now: now)
        expect(t.contains("— just now.") && t.contains("Ebbrim never sees that login — off.")
               && t.contains("Claude Code in Terminal: connected."), t)
        let none = AccessText.body(providers: [], codexEnabled: true, terminalConnected: false, now: now)
        expect(none.contains("keeps on this Mac — no data yet."), none)
    }
}
