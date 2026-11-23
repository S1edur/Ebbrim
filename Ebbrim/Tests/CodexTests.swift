import Foundation

private let fake = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Fixtures/fake-codex.sh")

private func reply(_ json: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

func codexTests() {
    let at = utc("2026-11-21T23:00:00Z")
    run("testParseRealShape") {
        let r = reply(#"{"accountId":"x","rateLimits":{"planType":"plus","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1763781300},"secondary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1764353700}},"rateLimitsByLimitId":{}}"#)
        let s = CodexRateLimits.parse(r, at: at)
        expect(s?.session == LimitWindow(id: "codex.session", span: .session, usedPercent: 0,
                                          resetsAt: Date(timeIntervalSince1970: 1763781300)), "session \(String(describing: s?.session))")
        expect(s?.weekly == LimitWindow(id: "codex.weekly", span: .weekly, usedPercent: 4,
                                         resetsAt: Date(timeIntervalSince1970: 1764353700)), "weekly")
        expect(s?.plan == "Plus" && s?.source == .codex && s?.capturedAt == at, "meta")
    }
    run("testParseMissingSecondary") {
        let s = CodexRateLimits.parse(reply(#"{"rateLimits":{"primary":{"usedPercent":7}}}"#), at: at)
        expect(s?.session?.usedPercent == 7 && s?.session?.resetsAt == nil && s?.weekly == nil, "session only")
    }
    run("testParseNoRateLimits") {
        expect(CodexRateLimits.parse(reply(#"{"rateLimits":null}"#), at: at) == nil, "null")
        expect(CodexRateLimits.parse(reply(#"{"rateLimits":{}}"#), at: at) == nil, "empty")
    }
    run("testDisplayPlanUnknown") {
        expect(CodexRateLimits.displayPlan("ent26") == nil && CodexRateLimits.displayPlan(nil) == nil, "unknown")
        expect(CodexRateLimits.displayPlan("prolite") == "Pro Lite" && CodexRateLimits.displayPlan("pro") == "Pro", "known")
    }
    run("testHelperAgainstFakeServer") {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("cn-fake-\(UUID()).log")
        let helper = CodexHelper(executable: fake, environment: ["FAKE_LOG": log.path])
        guard case .success(let r) = helper.readRateLimits(timeout: 5) else { expect(false, "not success"); return }
        expect(CodexRateLimits.parse(r, at: at)?.session?.usedPercent == 12, "parsed")
        let methods = (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").map(String.init)
        expect(methods == ["initialize", "initialized", "account/rateLimits/read"], "methods \(String(describing: methods))")
    }
    run("testHelperTimeoutKillsChild") {
        let helper = CodexHelper(executable: fake, environment: ["FAKE_MODE": "hang"])
        let t = Date()
        let r = helper.readRateLimits(timeout: 1)
        expect(r.failure == .timeout, "timeout: \(r)")
        expect(Date().timeIntervalSince(t) < 2.5, "returned in time")
        expect(helper.lastPid.map { kill($0, 0) != 0 } ?? false, "child gone")
    }
    run("testHelperSignedOut") {
        let helper = CodexHelper(executable: fake, environment: ["FAKE_MODE": "signedout"])
        expect(helper.readRateLimits(timeout: 5).failure == .signedOut, "signed out")
    }
}

extension Result {
    var failure: Failure? { if case .failure(let e) = self { return e }; return nil }
}
