import Foundation

private func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("cn-cache-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private func entry(_ query: String, date: String?, used: Int = 20) -> Data {
    let json = #"{"five_hour":{"utilization":\#(used),"resets_at":"2026-11-23T00:30:00.791496+00:00"},"seven_day":null}"#
    let headers = "HTTP/1.1 200\0" + (date.map { "date:\($0)\0" } ?? "") + "\0"
    return simpleCacheFile(key: "https://claude.ai/api/organizations/0000/usage\(query)",
                           body: zstdRawFrame(Data(json.utf8)), headers: headers)
}

private func evaluate(_ dir: URL) -> SourceResult {
    var known = Set<URL>()
    return DesktopCacheSource.evaluate(cacheDir: dir, knownPaths: &known, scanLimit: 3000)
}

private func snapshot(_ r: SourceResult) -> UsageSnapshot? {
    if case .snapshot(let s) = r { return s }
    return nil
}

func desktopCacheSourceTests() {
    run("testMissingDirIsNoSource") {
        expect(evaluate(URL(fileURLWithPath: "/nonexistent/cn-\(UUID())")) == .noSource, "missing dir")
    }
    run("testDirWithoutUsageEntryIsNoSource") {
        let d = tempDir()
        try simpleCacheFile(key: "https://claude.ai/api/bootstrap", body: Data([1]), headers: "\0").write(to: d.appendingPathComponent("a_0"))
        try Data("junk".utf8).write(to: d.appendingPathComponent("b_0"))
        try FileManager.default.createDirectory(at: d.appendingPathComponent("index-dir"), withIntermediateDirectories: true)
        expect(evaluate(d) == .noSource, "no usage entry")
    }
    run("testPicksNewestOfTwoEntries") {
        let d = tempDir()
        try entry("?via=plan", date: "Sat, 21 Nov 2026 21:48:23 GMT", used: 30).write(to: d.appendingPathComponent("a_0"))
        try entry("", date: "Sat, 21 Nov 2026 19:16:28 GMT", used: 10).write(to: d.appendingPathComponent("b_0"))
        let s = snapshot(evaluate(d))
        expect(s?.capturedAt == utc("2026-11-21T21:48:23Z") && s?.session?.usedPercent == 30, "newest wins: \(String(describing: s))")
    }
    run("testFallsBackToMtimeWithoutDate") {
        let d = tempDir(); let f = d.appendingPathComponent("a_0")
        try entry("?via=plan", date: nil).write(to: f)
        let mtime = utc("2026-11-20T10:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: f.path)
        expect(snapshot(evaluate(d))?.capturedAt == mtime, "mtime fallback")
    }
    run("testTruncatedThenFixedEntryReportsSnapshot") {
        let d = tempDir(); let f = d.appendingPathComponent("a_0")
        let full = entry("?via=plan", date: "Sat, 21 Nov 2026 21:48:23 GMT")
        try full.prefix(full.count - 60).write(to: f)          // body cut mid-frame
        var results: [SourceResult] = []
        let src = DesktopCacheSource(cacheDir: d, retryDelay: 0.2) { results.append($0) }
        src.readNow()
        try full.write(to: f)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        expect(results.count == 1 && snapshot(results.first ?? .noSource) != nil, "only a snapshot: \(results)")
    }
    run("testPermanentGarbageReportsFormatChanged") {
        let d = tempDir()
        try simpleCacheFile(key: "https://claude.ai/api/organizations/0000/usage?via=plan",
                            body: zstdRawFrame(Data("not json".utf8)), headers: "\0").write(to: d.appendingPathComponent("a_0"))
        var results: [SourceResult] = []
        let src = DesktopCacheSource(cacheDir: d, retryDelay: 0.1) { results.append($0) }
        src.readNow()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        if case .formatChanged = results.last ?? .noSource { expect(results.count == 1, "one report: \(results)") }
        else { expect(false, "expected formatChanged: \(results)") }
    }
}
