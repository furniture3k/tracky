import Foundation

/// App state: the session list, the running session, the idle-paused state and one level of undo.
@MainActor
final class Tracker: ObservableObject {
    @Published private(set) var sessions: [Session]
    /// Tag used for the next start.
    @Published private(set) var selectedTag: String
    /// Non-nil while auto-paused; holds the tag to resume with.
    @Published private(set) var pausedTag: String?
    /// Message for the undo toast ("Deleted 1h 20m · today").
    @Published private(set) var undoMessage: String?
    private var undoSnapshot: [Session]?

    /// Called after any state change (menu bar label, timer scheduling).
    var onChange: (() -> Void)?

    private let store: Store

    init(store: Store = Store()) {
        self.store = store
        let loaded = store.load()
        sessions = loaded
        Brand.assignColors(loaded)
        selectedTag = loaded.last(where: { $0.end == nil })?.tag
            ?? UserDefaults.standard.string(forKey: "lastTag") ?? ""
    }

    private var runningIndex: Int? { sessions.lastIndex { $0.end == nil } }
    var running: Session? { runningIndex.map { sessions[$0] } }
    var isRunning: Bool { runningIndex != nil }
    var isPaused: Bool { pausedTag != nil }
    var canUndo: Bool { undoSnapshot != nil }

    var recentTags: [String] {
        var seen = Set<String>(), out: [String] = []
        for s in sessions.reversed() where !s.tag.isEmpty && seen.insert(s.tag).inserted {
            out.append(s.tag)
            if out.count == 8 { break }
        }
        return out
    }

    /// Tracked seconds since `since` (cheap: scans only recent sessions).
    func tracked(since: Date, now: Date = Date()) -> Double {
        let cutoff = since.addingTimeInterval(-3 * 86400)
        var t = 0.0
        for s in sessions.reversed() {
            if s.start < cutoff { break }
            let e = s.end ?? now
            if e > since { t += e.timeIntervalSince(max(s.start, since)) }
        }
        return t
    }

    // MARK: Start / stop

    func toggle() {
        if isRunning { stop() } else { start(tag: pausedTag ?? selectedTag) }
    }

    func start(tag: String) {
        guard !isRunning else { return }
        pausedTag = nil
        sessions.append(Session(start: Date(), tag: tag))
        commit()
    }

    func stop() {
        pausedTag = nil
        finish(at: Date(), auto: false)
    }

    /// Ends the running session at `at` (backdated to last activity) and remembers its tag for resuming.
    func autoPause(at date: Date) {
        guard let r = running else { return }
        pausedTag = r.tag
        finish(at: max(date, r.start), auto: true)
    }

    func resume() {
        guard let t = pausedTag else { return }
        start(tag: t)
    }

    /// Throw away the running session entirely (started by accident). Undoable.
    func discardRunning() {
        guard let i = runningIndex else { return }
        snapshot("Discarded \(Stats.format(sessions[i].duration()))")
        sessions.remove(at: i)
        commit()
    }

    /// "I actually started 15 minutes ago" — never overlaps the previous session.
    func shiftStart(minutes: Int) {
        guard let i = runningIndex else { return }
        let floor = i > 0 ? (sessions[i - 1].end ?? sessions[i - 1].start) : .distantPast
        sessions[i].start = max(floor, sessions[i].start.addingTimeInterval(TimeInterval(-minutes * 60)))
        commit()
    }

    private func finish(at date: Date, auto: Bool) {
        guard let i = runningIndex else { commit(); return }
        if auto && date.timeIntervalSince(sessions[i].start) < 60 {
            sessions.remove(at: i) // a sub-minute blip before going idle isn't worth keeping
        } else {
            sessions[i].end = date
            sessions[i].auto = auto
        }
        commit()
    }

    // MARK: Tags

    /// Switching tag mid-session splits it, so your stats show the switch accurately.
    func selectTag(_ tag: String) {
        let t = Session.clean(tag)
        selectedTag = t
        UserDefaults.standard.set(t, forKey: "lastTag")
        if let i = runningIndex, sessions[i].tag != t {
            let now = Date()
            if now.timeIntervalSince(sessions[i].start) >= 60 {
                sessions[i].end = now
                sessions.append(Session(start: now, tag: t))
            } else {
                sessions[i].tag = t
            }
        }
        if pausedTag != nil { pausedTag = t }
        commit()
    }

    // MARK: Editing

    func upsert(_ s: Session) {
        var s = s
        s.tag = Session.clean(s.tag)
        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.append(s) }
        sessions.sort { $0.start < $1.start }
        commit()
    }

    func delete(_ id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }) else { return }
        snapshot("Deleted \(Stats.format(s.duration())) session")
        sessions.removeAll { $0.id == id }
        commit()
    }

    /// Removes all tracked time inside [from, to), trimming sessions that cross the edges.
    /// If you're tracking, tracking carries on from now.
    func removeRange(from: Date, to: Date, label: String) {
        let now = Date()
        var out: [Session] = []
        for s in sessions {
            let e = s.end ?? now
            guard e > from && s.start < to else { out.append(s); continue }
            if s.start < from {
                var a = s
                a.end = from
                out.append(a)
            }
            if e > to {
                var b = s
                b.id = UUID()
                b.start = to
                out.append(b)
            } else if s.end == nil {
                out.append(Session(start: now, tag: s.tag))
            }
        }
        let removed = total(sessions, now) - total(out, now)
        guard removed >= 1 else {
            undoSnapshot = nil
            undoMessage = "Nothing tracked \(label)"
            return
        }
        snapshot("Deleted \(Stats.format(removed)) · \(label)")
        sessions = out.sorted { $0.start < $1.start }
        commit()
    }

    func undo() {
        guard let snap = undoSnapshot else { return }
        sessions = snap
        undoSnapshot = nil
        undoMessage = nil
        commit()
    }

    func clearUndo() {
        undoSnapshot = nil
        undoMessage = nil
    }

    /// On quit, logout or shutdown, end the running session now rather than letting it
    /// silently span the time the Mac was off. (A crash still resumes it.)
    func endForQuit() {
        if isRunning { finish(at: Date(), auto: false) }
    }

    private func snapshot(_ message: String) {
        undoSnapshot = sessions
        undoMessage = message
    }

    private func total(_ list: [Session], _ now: Date) -> Double {
        list.reduce(0) { $0 + $1.duration(now: now) }
    }

    private func commit() {
        store.save(sessions)
        Brand.assignColors(sessions)
        onChange?()
    }
}
