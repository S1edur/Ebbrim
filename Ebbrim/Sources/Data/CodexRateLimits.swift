import Foundation

/// The `result` of Codex's `account/rateLimits/read` → snapshot.
/// `rateLimits.primary` is the 5-hour window, `secondary` the weekly one.
enum CodexRateLimits {
    static func parse(_ result: [String: Any], at: Date) -> UsageSnapshot? {
        guard let limits = result["rateLimits"] as? [String: Any] else { return nil }
        let session = window(limits["primary"], id: "codex.session", span: .session)
        let weekly = window(limits["secondary"], id: "codex.weekly", span: .weekly)
        guard session != nil || weekly != nil else { return nil }
        return UsageSnapshot(session: session, weekly: weekly, capturedAt: at, source: .codex,
                             plan: displayPlan(limits["planType"] as? String))
    }

    private static let plans = ["free": "Free", "go": "Go", "plus": "Plus", "pro": "Pro",
                                "prolite": "Pro Lite", "team": "Team", "business": "Business",
                                "enterprise": "Enterprise", "edu": "Edu"]

    static func displayPlan(_ raw: String?) -> String? { raw.flatMap { plans[$0] } }

    private static func window(_ value: Any?, id: String, span: LimitWindow.Span) -> LimitWindow? {
        guard let w = value as? [String: Any], let used = (w["usedPercent"] as? NSNumber)?.doubleValue
        else { return nil }
        let reset = (w["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return LimitWindow(id: id, span: span, usedPercent: used, resetsAt: reset)
    }
}
