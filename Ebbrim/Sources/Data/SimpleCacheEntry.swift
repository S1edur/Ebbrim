import Foundation

/// One Chromium Simple Cache entry file (format version 5), as Claude Desktop
/// stores HTTP responses: header, key (the URL), body (stream 1), an EOF
/// record, then the raw response headers.
struct SimpleCacheEntry {
    let key: String
    let body: Data
    let date: Date?                      // the response's `date:` header

    static let initialMagic: UInt64 = 0xfcfb6d1ba7725c30
    static let finalMagic: UInt64 = 0xf4fa6f45970d41d8
    static let headerSize = 24
    static let maxKeyLength = 2048

    /// The cached URL, from the first bytes of a file (600 are enough).
    static func key(fromHeader data: Data) -> String? {
        guard data.count >= headerSize,
              u64(data, 0) == initialMagic, u32(data, 8) == 5 else { return nil }
        let length = Int(u32(data, 12))
        guard length > 0, length <= maxKeyLength, data.count >= headerSize + length else { return nil }
        return String(data: sub(data, headerSize, length), encoding: .utf8)
    }

    static func parse(_ file: Data) -> SimpleCacheEntry? {
        guard let key = key(fromHeader: file) else { return nil }
        let start = file.startIndex + headerSize + key.utf8.count
        var magic = finalMagic.littleEndian
        let marker = Data(bytes: &magic, count: 8)
        guard let eof = file.range(of: marker, in: start..<file.endIndex) else { return nil }
        let body = file.subdata(in: start..<eof.lowerBound)
        let tail = file.subdata(in: eof.upperBound..<file.endIndex)
        return SimpleCacheEntry(key: key, body: body, date: dateHeader(in: tail))
    }

    private static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    private static func dateHeader(in tail: Data) -> Date? {
        let text = String(decoding: tail, as: UTF8.self)
        for field in text.split(separator: "\0") {
            guard field.lowercased().hasPrefix("date:") else { continue }
            let value = field.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return httpDate.date(from: value)
        }
        return nil
    }

    private static func sub(_ d: Data, _ offset: Int, _ count: Int) -> Data {
        d.subdata(in: d.startIndex + offset..<d.startIndex + offset + count)
    }
    private static func u32(_ d: Data, _ offset: Int) -> UInt32 {
        sub(d, offset, 4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }
    private static func u64(_ d: Data, _ offset: Int) -> UInt64 {
        sub(d, offset, 8).withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
    }
}
