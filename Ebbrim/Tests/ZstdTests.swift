import Foundation

func zstdTests() {
    run("testZstdRoundTripsRawFrame") {
        let out = Zstd.decompress(zstdRawFrame(Data("{\"a\":1}".utf8)))
        expect(out == Data("{\"a\":1}".utf8), "got \(String(describing: out))")
    }
    run("testZstdRejectsBadMagic") {
        expect(Zstd.decompress(Data([0, 1, 2, 3, 4, 5])) == nil, "bad magic must be nil")
    }
    run("testZstdEnforcesCap") {
        let big = Data(repeating: 0x41, count: 300_000)
        expect(Zstd.decompress(zstdRawFrame(big), maxOutput: 262_144) == nil, "over cap must be nil")
        expect(Zstd.decompress(zstdRawFrame(big), maxOutput: 400_000)?.count == 300_000, "under cap decodes")
    }
}
