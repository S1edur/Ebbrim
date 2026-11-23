import Foundation

/// claude.ai's `/api/organizations/<id>/usage` response → snapshot.
/// Only `five_hour` and `seven_day` are used: `{utilization, resets_at}`.
enum ClaudeUsageJSON {
    static func parse(_ json: Data, capturedAt: Date,
                      source: UsageSnapshot.Source = .desktopCache) -> UsageSnapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        let session = window(root["five_hour"], id: "claude.session", span: .session)
        let weekly = window(root["seven_day"], id: "claude.weekly", span: .weekly)
        guard session != nil || weekly != nil else { return nil }
        return UsageSnapshot(session: session, weekly: weekly, capturedAt: capturedAt, source: source,
                             plan: inferredPlan(session: session, weekly: weekly))
    }

    /// The usage response names no plan. Product rule (Denys, 2026-11-23):
    /// Max 20x has no 5-hour session, so weekly-only means "Max 20x"; with a
    /// 5-hour window the plan is not known and no badge is shown.
    static func inferredPlan(session: LimitWindow?, weekly: LimitWindow?) -> String? {
        session == nil && weekly != nil ? "Max 20x" : nil
    }

    private static func window(_ value: Any?, id: String, span: LimitWindow.Span) -> LimitWindow? {
        guard let w = value as? [String: Any], let used = (w["utilization"] as? NSNumber)?.doubleValue
        else { return nil }
        return LimitWindow(id: id, span: span, usedPercent: used,
                           resetsAt: (w["resets_at"] as? String).flatMap(ISODate.parse))
    }
}
