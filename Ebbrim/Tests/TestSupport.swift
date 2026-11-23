import Foundation

var testsPassed = 0
var testsFailed = 0
private var currentFailed = false

func expect(_ ok: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if !ok {
        currentFailed = true
        print("  ✗ \((file as NSString).lastPathComponent):\(line) \(msg)")
    }
}

func run(_ name: String, _ body: () throws -> Void) {
    currentFailed = false
    do { try body() } catch { expect(false, "threw \(error)") }
    if currentFailed { testsFailed += 1; print("FAIL \(name)") } else { testsPassed += 1 }
}

/// A valid zstd frame that stores `payload` in raw (uncompressed) blocks.
func zstdRawFrame(_ payload: Data) -> Data {
    var d = Data([0x28, 0xB5, 0x2F, 0xFD, 0xA0])       // magic; single segment, 4-byte size
    var size = UInt32(payload.count).littleEndian
    d.append(Data(bytes: &size, count: 4))
    let maxBlock = 128 * 1024
    var offset = 0
    repeat {
        let n = min(maxBlock, payload.count - offset)
        let last: UInt32 = offset + n == payload.count ? 1 : 0
        let header = last | (0 << 1) | (UInt32(n) << 3)
        d.append(contentsOf: [UInt8(header & 0xFF), UInt8((header >> 8) & 0xFF), UInt8((header >> 16) & 0xFF)])
        d.append(payload.subdata(in: offset..<offset + n))
        offset += n
    } while offset < payload.count
    return d
}

private func le<T: FixedWidthInteger>(_ v: T) -> Data {
    var x = v.littleEndian
    return Data(bytes: &x, count: MemoryLayout<T>.size)
}

/// A Chromium Simple Cache entry file (version 5) as Claude Desktop writes it.
func simpleCacheFile(key: String, body: Data, headers: String,
                     magic: UInt64 = 0xfcfb6d1ba7725c30, keyLength: UInt32? = nil) -> Data {
    let k = Data(key.utf8)
    var d = le(magic) + le(UInt32(5)) + le(keyLength ?? UInt32(k.count)) + le(UInt32(0)) + le(UInt32(0))
    d += k
    d += body
    d += le(UInt64(0xf4fa6f45970d41d8)) + le(UInt32(0)) + le(UInt32(0)) + le(UInt32(0)) + le(UInt32(0))
    d += Data(headers.utf8)
    return d
}

func utc(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    return f.date(from: s)!
}

let sampleClaudeJSON = """
{"five_hour":{"utilization":37.5,"resets_at":"2026-11-23T00:30:00.791496+00:00","used_dollars":null},
 "seven_day":{"utilization":10,"resets_at":"2026-11-25T19:00:00.791516+00:00"},
 "limits":[{"percent":9}],"spend":null}
"""
let usageKey = "1/0/_dk_https://claude.ai https://claude.ai https://claude.ai/api/organizations/0000/usage?via=plan"
