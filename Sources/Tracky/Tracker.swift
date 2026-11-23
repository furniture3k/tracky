import Foundation

/// App state: the session list, the running session, tags, the idle-paused state and one level of undo.
@MainActor
final class Tracker: ObservableObject {
    @Published private(set) var sessions: [Session]
    /// Your tag list, in a stable order (the order you created them). Chips never reshuffle.
    @Published private(set) var tags: [String]
    /// Tag used for the next start.
    @Published private(set) var selectedTag: String
    /// Non-nil while auto-paused; holds the tag to resume with.
    @Published private(set) var pausedTag: String?
    /// Message for the undo toast ("Deleted 1h 20m · today").
    @Published private(set) var undoMessage: String?
    /// Changes on every toast so its auto-dismiss timer restarts even if the text repeats.
    @Published private(set) var undoID = UUID()
    private var undoSnapshot: [Session]?

    /// Called after any state change (menu bar label, timer scheduling).
    var onChange: (() -> Void)?

    private let store: Store
    private let defaults: UserDefaults

    /// Within this long of starting, picking a tag relabels the running session instead of splitting it.
    static let retagWindow: TimeInterval = 10 * 60

    init(store: Store = Store(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let loaded = store.load()
        sessions = loaded
        if let saved = defaults.stringArray(forKey: "tags") {
            tags = saved
        } else {
            var seen = Set<String>(), list: [String] = []
            for s in loaded where !s.tag.isEmpty && seen.insert(s.tag).inserted { list.append(s.tag) }
            tags = list
        }
        selectedTag = loaded.last(where: { $0.end == nil })?.tag ?? defaults.string(forKey: "lastTag") ?? ""
        Brand.assignColors(tags: tags, sessions: loaded)
    }

    private var runningIndex: Int? { sessions.lastIndex { $0.end == nil } }
    var running: Session? { runningIndex.map { sessions[$0] } }
    var isRunning: Bool { runningIndex != nil }
    var isPaused: Bool { pausedTag != nil }
    var canUndo: Bool { undoSnapshot != nil }

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

    func start(tag: String, at date: Date = Date()) {
        guard !isRunning else { return }
        pausedTag = nil
        let floor = sessions.last.map { $0.end ?? $0.start } ?? .distantPast
        sessions.append(Session(start: max(date, floor), tag: tag))
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

    func resume(at date: Date = Date()) {
        guard let t = pausedTag else { return }
        start(tag: t, at: date)
    }

    /// Throw away the running session entirely (started by accident). Undoable.
    func discardRunning() {
        guard let i = runningIndex else { return }
        snapshot("Discarded \(Stats.format(sessions[i].duration()))")
        sessions.remove(at: i)
        commit()
    }

    /// "I actually started 15 minutes ago". Never overlaps the previous session.
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

    /// Picks a tag for the next/current session, creating it if new.
    /// While tracking: in the first 10 minutes the running session is simply relabelled; after that
    /// the session is split so the time already spent keeps its old tag (undoable).
    func selectTag(_ raw: String) {
        let t = canonical(raw)
        if !t.isEmpty && !tags.contains(t) { tags.append(t) }
        selectedTag = t
        defaults.set(t, forKey: "lastTag")
        if let i = runningIndex, sessions[i].tag != t {
            let now = Date()
            let old = sessions[i]
            if now.timeIntervalSince(old.start) < Self.retagWindow {
                sessions[i].tag = t
            } else {
                snapshot("Switched to \(t.isEmpty ? "no tag" : t) · \(Stats.format(old.duration(now: now))) kept as \(old.tag.isEmpty ? "no tag" : old.tag)")
                sessions[i].end = now
                sessions.append(Session(start: now, tag: t))
            }
        }
        if pausedTag != nil { pausedTag = t }
        commit()
    }

    /// Renames a tag everywhere (merging into an existing tag with that name if there is one).
    func renameTag(_ old: String, to raw: String) {
        let new = Session.clean(raw)
        guard !new.isEmpty, new != old else { return }
        let target = tags.first { $0 != old && $0.caseInsensitiveCompare(new) == .orderedSame } ?? new
        for i in sessions.indices where sessions[i].tag == old { sessions[i].tag = target }
        if let i = tags.firstIndex(of: old) {
            if tags.contains(target) { tags.remove(at: i) } else { tags[i] = target }
        }
        if selectedTag == old { selectedTag = target; defaults.set(target, forKey: "lastTag") }
        if pausedTag == old { pausedTag = target }
        commit()
    }

    /// Removes a tag from the list. Past sessions keep their label, so your stats don't change.
    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        if selectedTag == tag { selectedTag = ""; defaults.set("", forKey: "lastTag") }
        commit()
    }

    func moveTag(_ tag: String, by offset: Int) {
        guard let i = tags.firstIndex(of: tag) else { return }
        let j = min(max(i + offset, 0), tags.count - 1)
        guard i != j else { return }
        tags.swapAt(i, j)
        commit()
    }

    /// Reuses an existing tag that differs only by case ("uni" → "Uni").
    private func canonical(_ raw: String) -> String {
        let t = Session.clean(raw)
        return tags.first { $0.caseInsensitiveCompare(t) == .orderedSame } ?? t
    }

    // MARK: Editing

    func upsert(_ s: Session) {
        var s = s
        s.tag = canonical(s.tag)
        if !s.tag.isEmpty && !tags.contains(s.tag) { tags.append(s.tag) }
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
            undoID = UUID()
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
        undoID = UUID()
    }

    private func total(_ list: [Session], _ now: Date) -> Double {
        list.reduce(0) { $0 + $1.duration(now: now) }
    }

    private func commit() {
        store.save(sessions)
        defaults.set(tags, forKey: "tags")
        Brand.assignColors(tags: tags, sessions: sessions)
        onChange?()
    }
}
