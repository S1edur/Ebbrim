import Foundation

func planInferenceTests() {
    let at = utc("2026-11-23T10:00:00Z")
    run("testWeeklyOnlyIsMax20x") {
        let s = ClaudeUsageJSON.parse(Data(#"{"five_hour":null,"seven_day":{"utilization":40,"resets_at":"2026-11-25T19:00:00+00:00"}}"#.utf8), capturedAt: at)
        expect(s?.session == nil && s?.weekly?.usedPercent == 40 && s?.plan == "Max 20x", "\(String(describing: s))")
    }
    run("testSessionMeansPlanUnknown") {
        let s = ClaudeUsageJSON.parse(Data(#"{"five_hour":{"utilization":9},"seven_day":{"utilization":10}}"#.utf8), capturedAt: at)
        expect(s?.session != nil && s?.plan == nil, "plan unknown when a 5-hour window exists")
    }
    run("testMissingFiveHourKeyIsAlsoWeeklyOnly") {
        let s = ClaudeUsageJSON.parse(Data(#"{"seven_day":{"utilization":3}}"#.utf8), capturedAt: at)
        expect(s?.plan == "Max 20x", "no five_hour key")
    }
    run("testMockCan20x") {
        let frame = UsageFeed.mockFrame(0, claude20x: true)
        let c = frame.first { $0.kind == .claude }
        expect(c?.windows.map(\.span) == [.weekly] && c?.plan == "Max 20x", "\(String(describing: c))")
    }
}
