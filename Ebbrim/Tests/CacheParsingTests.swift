import Foundation

func cacheParsingTests() {
    let headers = "HTTP/1.1 200\0content-type: application/json\0date:Sat, 21 Nov 2026 21:48:23 GMT\0content-encoding:zstd\0\0"

    run("testKeyFromHeader") {
        let file = simpleCacheFile(key: usageKey, body: zstdRawFrame(Data(sampleClaudeJSON.utf8)), headers: headers)
        expect(SimpleCacheEntry.key(fromHeader: file.prefix(600)) == usageKey, "key")
    }
    run("testKeyRejectsWrongMagic") {
        let file = simpleCacheFile(key: usageKey, body: Data(), headers: "", magic: 0x1234)
        expect(SimpleCacheEntry.key(fromHeader: file.prefix(600)) == nil, "wrong magic")
    }
    run("testKeyRejectsHugeLength") {
        let file = simpleCacheFile(key: usageKey, body: Data(), headers: "", keyLength: 5000)
        expect(SimpleCacheEntry.key(fromHeader: file.prefix(600)) == nil, "huge key length")
    }
    run("testParseFindsBodyAndDate") {
        let frame = zstdRawFrame(Data(sampleClaudeJSON.utf8))
        let e = SimpleCacheEntry.parse(simpleCacheFile(key: usageKey, body: frame, headers: headers))
        expect(e?.key == usageKey, "key")
        expect(e?.body == frame, "body")
        expect(e?.date == utc("2026-11-21T21:48:23Z"), "date \(String(describing: e?.date))")
    }
    run("testParseDateWithSpace") {
        let h = "HTTP/1.1 200\0Date: Sat, 21 Nov 2026 21:48:23 GMT\0\0"
        let e = SimpleCacheEntry.parse(simpleCacheFile(key: usageKey, body: zstdRawFrame(Data("{}".utf8)), headers: h))
        expect(e?.date == utc("2026-11-21T21:48:23Z"), "date with space")
    }
    run("testParseWithoutDate") {
        let e = SimpleCacheEntry.parse(simpleCacheFile(key: usageKey, body: zstdRawFrame(Data("{}".utf8)), headers: "HTTP/1.1 200\0\0"))
        expect(e != nil && e?.date == nil, "entry without date")
    }
    run("testParseTruncatedBody") {
        let file = simpleCacheFile(key: usageKey, body: zstdRawFrame(Data(sampleClaudeJSON.utf8)), headers: headers)
        expect(SimpleCacheEntry.parse(file.prefix(24 + usageKey.utf8.count + 20)) == nil, "truncated")
    }
    run("testClaudeJSONMapsWindows") {
        let at = utc("2026-11-22T20:50:52Z")
        let s = ClaudeUsageJSON.parse(Data(sampleClaudeJSON.utf8), capturedAt: at)
        expect(s?.session == LimitWindow(id: "claude.session", span: .session, usedPercent: 37.5,
                                          resetsAt: Date(timeIntervalSince1970: utc("2026-11-23T00:30:00Z").timeIntervalSince1970 + 0.791496)),
               "session \(String(describing: s?.session))")
        expect(s?.weekly?.id == "claude.weekly" && s?.weekly?.span == .weekly && s?.weekly?.usedPercent == 10, "weekly")
        expect(s?.source == .desktopCache && s?.capturedAt == at && s?.plan == nil, "meta")
    }
    run("testClaudeJSONNullWindow") {
        let s = ClaudeUsageJSON.parse(Data(#"{"five_hour":{"utilization":5,"resets_at":"2026-11-23T00:30:00+00:00"},"seven_day":null}"#.utf8), capturedAt: Date())
        expect(s?.weekly == nil && s?.session?.usedPercent == 5, "null weekly")
    }
    run("testClaudeJSONWithoutFractionalSeconds") {
        let s = ClaudeUsageJSON.parse(Data(#"{"five_hour":{"utilization":5,"resets_at":"2026-11-22T03:00:00+00:00"}}"#.utf8), capturedAt: Date())
        expect(s?.session?.resetsAt == utc("2026-11-22T03:00:00Z"), "no fraction")
    }
    run("testClaudeJSONGarbage") {
        expect(ClaudeUsageJSON.parse(Data("[1,2]".utf8), capturedAt: Date()) == nil, "array")
        expect(ClaudeUsageJSON.parse(Data(#"{"x":1}"#.utf8), capturedAt: Date()) == nil, "no windows")
    }
}
