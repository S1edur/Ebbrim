import Foundation
import CoreServices

/// Claude usage from Claude Desktop's HTTP cache. Read-only: it opens the first
/// 600 bytes of cache files to find the usage entries, and reads only those
/// entries in full. Watches the folder with FSEvents; no polling. File work
/// runs on a background queue (a full scan of ~90k entries takes ~1 s);
/// results are delivered on the main queue.
final class DesktopCacheSource {
    static let defaultDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Claude/Cache/Cache_Data")

    private let cacheDir: URL
    private let retryDelay: TimeInterval
    private let minRescanInterval: TimeInterval
    private var lastScan: Date?                       // queue-confined, like `known`
    private let onResult: (SourceResult) -> Void
    private var known = Set<URL>()
    private var stream: FSEventStreamRef?
    private var rescanTimer: Timer?
    private var retryPending = false
    private let queue = DispatchQueue(label: "ebbrim.desktopcache", qos: .utility)

    init(cacheDir: URL = DesktopCacheSource.defaultDir, retryDelay: TimeInterval = 1,
         minRescanInterval: TimeInterval = 60, onResult: @escaping (SourceResult) -> Void) {
        self.cacheDir = cacheDir
        self.retryDelay = retryDelay
        self.minRescanInterval = minRescanInterval
        self.onResult = onResult
    }

    deinit { stop() }

    func start() {
        guard rescanTimer == nil else { return }      // already running
        readNow(scanLimit: 3000)
        startWatching()
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.readNow(scanLimit: 800)
        }
    }

    func stop() {
        rescanTimer?.invalidate(); rescanTimer = nil
        if let s = stream {
            FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
            stream = nil
        }
    }

    /// Re-read the known usage entries now (rescanning if none is known yet).
    /// A failure is reported only if it repeats `retryDelay` later, so an entry
    /// caught mid-rewrite never shows up as "format changed".
    func readNow() { readNow(scanLimit: 0) }

    private func readNow(scanLimit: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            // A full scan stats ~90k files (~1 s), so while no usage entry is
            // known, event-driven reads rescan at most once per minRescanInterval.
            var limit = scanLimit
            if limit == 0, self.known.isEmpty,
               self.lastScan.map({ Date().timeIntervalSince($0) >= self.minRescanInterval }) ?? true {
                limit = 800
            }
            if limit > 0 { self.lastScan = Date() }
            let result = Self.evaluate(cacheDir: self.cacheDir, knownPaths: &self.known, scanLimit: limit)
            if case .formatChanged = result {
                guard !self.retryPending else { return }
                self.retryPending = true
                self.queue.asyncAfter(deadline: .now() + self.retryDelay) { [weak self] in
                    guard let self else { return }
                    self.retryPending = false
                    let again = Self.evaluate(cacheDir: self.cacheDir, knownPaths: &self.known, scanLimit: 0)
                    DispatchQueue.main.async { self.onResult(again) }
                }
            } else {
                DispatchQueue.main.async { self.onResult(result) }
            }
        }
    }

    // MARK: - Pure step

    static func evaluate(cacheDir: URL, knownPaths: inout Set<URL>, scanLimit: Int) -> SourceResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: cacheDir.path, isDirectory: &isDir), isDir.boolValue else { return .noSource }
        if scanLimit > 0 { knownPaths.formUnion(scan(cacheDir, limit: scanLimit)) }
        knownPaths = knownPaths.filter { fm.fileExists(atPath: $0.path) }
        guard !knownPaths.isEmpty else { return .noSource }

        let snapshots = knownPaths.compactMap(read)
        guard let newest = snapshots.max(by: { $0.capturedAt < $1.capturedAt }) else {
            return .formatChanged("Claude Desktop usage entry could not be read")
        }
        return .snapshot(newest)
    }

    private static let usageKey = try! NSRegularExpression(pattern: #"/api/organizations/[^/?]+/usage(\?|$)"#)

    static func isUsageKey(_ key: String) -> Bool {
        usageKey.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }

    /// The newest `limit` regular files whose cached URL is a usage endpoint.
    private static func scan(_ dir: URL, limit: Int) -> Set<URL> {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let all = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let files: [(URL, Date)] = all.compactMap {
            guard let v = try? $0.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
            return ($0, v.contentModificationDate ?? .distantPast)
        }
        var found = Set<URL>()
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(limit) {
            guard let h = FileHandle(forReadingAtPath: url.path) else { continue }
            let head = h.readData(ofLength: 600)
            try? h.close()
            if let key = SimpleCacheEntry.key(fromHeader: head), isUsageKey(key) { found.insert(url) }
        }
        return found
    }

    private static func read(_ url: URL) -> UsageSnapshot? {
        guard let file = try? Data(contentsOf: url),
              let entry = SimpleCacheEntry.parse(file),
              let json = Zstd.decompress(entry.body) else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let at = entry.date ?? mtime else { return nil }
        return ClaudeUsageJSON.parse(json, capturedAt: at)
    }

    // MARK: - FSEvents

    private func startWatching() {
        guard stream == nil else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DesktopCacheSource>.fromOpaque(info).takeUnretainedValue().readNow()
        }
        guard let s = FSEventStreamCreate(nil, callback, &ctx, [cacheDir.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }
}
