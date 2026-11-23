import Foundation

/// Persistence in a compact binary file (`data.trk`). About 6 bytes per session:
///
///     "TRK" 0x01                         magic + version
///     varint tagCount, then per tag:    varint byteLength + UTF-8
///     per session (sorted by start):    varint startDelta  seconds since previous session's start
///                                       varint duration    seconds (0 while running)
///                                       varint meta        tagIndex << 2 | auto << 1 | running
///
/// The whole file is rewritten atomically on change; it stays a few KB even after years.
struct Store {
    let url: URL
    private let legacyURL: URL?

    init(url: URL? = nil, legacy: URL? = nil) {
        if let url { self.url = url; legacyURL = legacy; return }
        if let path = ProcessInfo.processInfo.environment["TRACKY_DATA"] { // for demos/testing
            self.url = URL(fileURLWithPath: path); legacyURL = nil; return
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tracky", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("data.trk")
        legacyURL = dir.appendingPathComponent("sessions.csv")
    }

    func load() -> [Session] {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: url) {
            if let sessions = Codec.decode(data) { return sessions }
            // Never silently overwrite data we can't read: keep a copy aside.
            try? fm.moveItem(at: url, to: url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))"))
            return []
        }
        // One-time migration from the v1 CSV format.
        if let legacyURL, let text = try? String(contentsOf: legacyURL, encoding: .utf8) {
            let sessions = text.split(separator: "\n").compactMap(Session.init(csvLine:)).sorted { $0.start < $1.start }
            save(sessions)
            if (try? Data(contentsOf: url)).flatMap(Codec.decode)?.count == sessions.count {
                try? fm.removeItem(at: legacyURL)
            }
            return sessions
        }
        return []
    }

    func save(_ sessions: [Session]) {
        try? Codec.encode(sessions).write(to: url, options: .atomic)
    }
}

enum Codec {
    static let magic: [UInt8] = [0x54, 0x52, 0x4B, 0x01] // "TRK" v1

    static func encode(_ sessions: [Session]) -> Data {
        let sorted = sessions.sorted { $0.start < $1.start }
        var tags: [String] = [], index: [String: UInt64] = [:]
        for s in sorted where index[s.tag] == nil {
            index[s.tag] = UInt64(tags.count)
            tags.append(s.tag)
        }
        var out = magic
        out.reserveCapacity(16 + sorted.count * 7)
        put(&out, UInt64(tags.count))
        for t in tags {
            let b = Array(t.utf8)
            put(&out, UInt64(b.count))
            out += b
        }
        var prev: Int64 = 0
        for s in sorted {
            let start = max(0, Int64(s.start.timeIntervalSince1970))
            put(&out, UInt64(max(0, start - prev)))
            prev = start
            let dur = s.end.map { max(0, Int64($0.timeIntervalSince1970) - start) } ?? 0
            put(&out, UInt64(dur))
            put(&out, index[s.tag]! << 2 | (s.auto ? 2 : 0) | (s.end == nil ? 1 : 0))
        }
        return Data(out)
    }

    static func decode(_ data: Data) -> [Session]? {
        let b = [UInt8](data)
        guard b.count >= 4, Array(b[0..<4]) == magic else { return nil }
        var i = 4
        func next() -> UInt64? {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.count, shift < 64 {
                let byte = b[i]; i += 1
                v |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return v }
                shift += 7
            }
            return nil
        }
        guard let tagCount = next(), tagCount < 1_000_000 else { return nil }
        var tags: [String] = []
        for _ in 0..<tagCount {
            guard let n = next(), i + Int(n) <= b.count else { return nil }
            tags.append(String(decoding: b[i..<i + Int(n)], as: UTF8.self))
            i += Int(n)
        }
        var sessions: [Session] = []
        var start: Int64 = 0
        while i < b.count {
            guard let delta = next(), let dur = next(), let meta = next(), Int(meta >> 2) < tags.count else { return nil }
            start += Int64(delta)
            let st = Date(timeIntervalSince1970: TimeInterval(start))
            let running = meta & 1 == 1
            sessions.append(Session(start: st,
                                    end: running ? nil : st.addingTimeInterval(TimeInterval(dur)),
                                    tag: tags[Int(meta >> 2)],
                                    auto: meta & 2 == 2))
        }
        return sessions
    }

    private static func put(_ out: inout [UInt8], _ value: UInt64) {
        var v = value
        while v >= 0x80 { out.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        out.append(UInt8(v))
    }
}
