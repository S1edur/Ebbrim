import Foundation

/// One reading from one source, before freshness is decided.
struct UsageSnapshot: Equatable {
    enum Source: Equatable { case desktopCache, statusLine, codex }
    var session: LimitWindow?
    var weekly: LimitWindow?
    var capturedAt: Date                 // when the numbers were true
    var source: Source
    var plan: String? = nil
}

/// What a source reports to the aggregator.
enum SourceResult: Equatable {
    case snapshot(UsageSnapshot)
    case noSource                        // nothing to read (app not installed / not opened yet)
    case formatChanged(String)           // something is there but can't be read; reason for the log
}

/// ISO 8601 with any number of fractional-second digits ("…00.791496+00:00").
enum ISODate {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    static func parse(_ s: String) -> Date? {
        guard let dot = s.firstIndex(of: ".") else { return plain.date(from: s) }
        let base = String(s[..<dot])
        let rest = s[s.index(after: dot)...]
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, let frac = Double("0." + digits),
              let whole = plain.date(from: base + rest.dropFirst(digits.count)) else { return nil }
        return Date(timeIntervalSince1970: whole.timeIntervalSince1970 + frac)
    }
}
