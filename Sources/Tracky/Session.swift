import Foundation

/// One block of work. `end == nil` means it is still running.
struct Session: Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date?
    var tag: String = ""
    /// True when the session was ended by idle auto-pause rather than by you.
    var auto: Bool = false

    func duration(now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }

    init(start: Date, end: Date? = nil, tag: String = "", auto: Bool = false) {
        self.start = start
        self.end = end
        self.tag = Session.clean(tag)
        self.auto = auto
    }

    /// Parses the legacy v1 CSV line `start,end,tag,flag` (used once for migration).
    init?(csvLine line: Substring) {
        let f = line.split(separator: ",", omittingEmptySubsequences: false)
        guard f.count >= 1, let s = Double(f[0]) else { return nil }
        start = Date(timeIntervalSince1970: s)
        end = f.count > 1 ? Double(f[1]).map(Date.init(timeIntervalSince1970:)) : nil
        tag = f.count > 2 ? String(f[2]) : ""
        auto = f.count > 3 && f[3] == "a"
    }

    static func clean(_ tag: String) -> String {
        tag.replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
