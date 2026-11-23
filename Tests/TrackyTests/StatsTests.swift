import Foundation
import Testing
@testable import Tracky

private var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    c.minimumDaysInFirstWeek = 4
    return c
}()

private func d(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")!
    return f.date(from: s + ":00Z")!
}

private func s(_ a: String, _ b: String?, _ tag: String = "") -> Session {
    Session(start: d(a), end: b.map(d), tag: tag)
}

@Test func midnightSplit() {
    let days = Stats.dayTotals([s("2026-11-16T23:00", "2026-11-17T01:30")], to: d("2026-11-20T00:00"), cal: cal)
    #expect(days[d("2026-11-16T00:00")] == 3600)
    #expect(days[d("2026-11-17T00:00")] == 5400)
}

@Test func runningSessionCountsUpToNow() {
    let days = Stats.dayTotals([s("2026-11-23T09:00", nil)], to: d("2026-11-23T10:15"), cal: cal)
    #expect(days[d("2026-11-23T00:00")] == 4500)
}

@Test func weekStartsMonday() {
    // 2026-11-22 is a Sunday; its week starts Monday 2026-11-16.
    #expect(Stats.weekStart(d("2026-11-22T20:00"), cal: cal) == d("2026-11-16T00:00"))
    #expect(Stats.weekdayIndex(d("2026-11-16T12:00"), cal: cal) == 0)
    #expect(Stats.weekdayIndex(d("2026-11-22T12:00"), cal: cal) == 6)
}

@Test func weeklyAverageUsesCompletedWeeksOnly() {
    let now = d("2026-11-25T12:00") // Wednesday of week starting 11-23
    let sessions = [
        s("2026-11-09T09:00", "2026-11-09T19:00"), // week of 11-09: 10h
        s("2026-11-17T09:00", "2026-11-17T15:00"), // week of 11-16: 6h
        s("2026-11-24T09:00", "2026-11-24T21:00"), // current week: 12h (excluded from avg)
    ]
    let r = Report(sessions: sessions, rangeWeeks: 12, now: now, cal: cal)
    // Window clips to first data week (11-09), so 2 completed weeks, not 12.
    #expect(r.completedWeeks == 2)
    #expect(r.weeklyAverage == 8 * 3600)
    #expect(r.thisWeek == 12 * 3600)
    #expect(r.weeks.count == 3)
    #expect(r.weekday[0] == 5) // Mondays: 10h over 2 weeks
    #expect(r.weekday[1] == 3) // Tuesdays: 6h over 2 weeks
}

@Test func rangeLimitsWindow() {
    let now = d("2026-11-25T12:00")
    let sessions = [s("2026-01-05T09:00", "2026-01-05T19:00"), s("2026-11-17T09:00", "2026-11-17T13:00")]
    let r = Report(sessions: sessions, rangeWeeks: 4, now: now, cal: cal)
    #expect(r.completedWeeks == 4)
    #expect(r.weeklyAverage == 3600)
}

@Test func byTagShares() {
    let now = d("2026-11-25T12:00")
    let r = Report(sessions: [s("2026-11-24T09:00", "2026-11-24T12:00", "Uni"),
                              s("2026-11-24T13:00", "2026-11-24T14:00")], rangeWeeks: 4, now: now, cal: cal)
    #expect(r.byTag.first?.tag == "Uni")
    #expect(r.byTag.first?.share == 0.75)
    #expect(r.byTag.last?.tag == "Untagged")
    #expect(r.heat[1][9] == 3600)
}

@Test func streak() {
    let now = d("2026-11-25T08:00")
    let sessions = [s("2026-11-22T09:00", "2026-11-22T10:00"),
                    s("2026-11-23T09:00", "2026-11-23T10:00"),
                    s("2026-11-24T09:00", "2026-11-24T10:00")]
    #expect(Stats.streak(sessions, now: now, cal: cal) == 3) // today empty → counts from yesterday
    #expect(Stats.streak(sessions + [s("2026-11-25T07:00", "2026-11-25T07:30")], now: now, cal: cal) == 4)
    #expect(Stats.streak([s("2026-11-20T09:00", "2026-11-20T10:00")], now: now, cal: cal) == 0)
}

@Test func csvRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracky-\(UUID()).csv")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = Store(url: url)
    var done = s("2026-11-24T09:00", "2026-11-24T10:00", "Deep, work")
    done.auto = true
    store.save([done, s("2026-11-24T11:00", nil, "Uni")])
    let back = store.load()
    #expect(back.count == 2)
    #expect(back[0].tag == "Deep  work")
    #expect(back[0].auto)
    #expect(back[0].end == d("2026-11-24T10:00"))
    #expect(back[1].end == nil) // running session survives a restart
    #expect(back[1].tag == "Uni")
}

@Test func format() {
    #expect(Stats.format(59) == "0m")
    #expect(Stats.format(45 * 60) == "45m")
    #expect(Stats.format(83 * 60) == "1h 23m")
    #expect(Stats.clock(3725) == "1:02:05")
}

@Test func binaryFormatIsTiny() {
    // 1,000 realistic sessions (~2h each, a few per day, 4 tags).
    var list: [Session] = []
    var t = d("2024-01-01T09:00")
    for i in 0..<1000 {
        list.append(Session(start: t, end: t.addingTimeInterval(Double(3600 + i % 7 * 900)), tag: ["Uni", "Client", "Side", ""][i % 4], auto: i % 9 == 0))
        t = t.addingTimeInterval(Double(3 * 3600 + i % 5 * 1800))
    }
    let data = Codec.encode(list)
    #expect(data.count < 7 * 1000, "got \(data.count) bytes")
    let back = Codec.decode(data)!
    #expect(back.count == 1000)
    #expect(zip(list, back).allSatisfy { $0.start == $1.start && $0.end == $1.end && $0.tag == $1.tag && $0.auto == $1.auto })
}

@Test func corruptDataIsRejected() {
    #expect(Codec.decode(Data([0x54, 0x52, 0x4B, 0x01, 0x05])) == nil)
    #expect(Codec.decode(Data("hello".utf8)) == nil)
}

@Test func migratesLegacyCSV() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tracky-mig-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let csv = dir.appendingPathComponent("sessions.csv")
    try "1763890000,1763893600,Uni,\n1763900000,,Client,\n".write(to: csv, atomically: true, encoding: .utf8)
    let store = Store(url: dir.appendingPathComponent("data.trk"), legacy: csv)
    let s = store.load()
    #expect(s.count == 2)
    #expect(s[1].end == nil)
    #expect(!FileManager.default.fileExists(atPath: csv.path))
    #expect(store.load().count == 2) // now read from binary
}

@MainActor
private func tracker(_ sessions: [Session]) -> Tracker {
    let store = Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("tracky-\(UUID()).trk"))
    store.save(sessions)
    return Tracker(store: store, defaults: UserDefaults(suiteName: "tracky-test-\(UUID())")!)
}

@MainActor @Test func removeRangeTrimsAndUndoes() {
    let t = tracker([s("2026-11-24T08:00", "2026-11-24T10:00", "A"),
                     s("2026-11-24T11:00", "2026-11-24T12:00", "B"),
                     s("2026-11-23T09:00", "2026-11-23T10:00", "C")])
    t.removeRange(from: d("2026-11-24T09:00"), to: d("2026-11-24T23:59"), label: "today")
    #expect(t.sessions.count == 2)
    #expect(t.sessions.last?.end == d("2026-11-24T09:00")) // A trimmed to 08–09
    #expect(t.canUndo)
    t.undo()
    #expect(t.sessions.count == 3)
}

@MainActor @Test func removeRangeKeepsTrackingFromNow() {
    let t = tracker([Session(start: Date().addingTimeInterval(-7200), tag: "Deep")])
    t.removeRange(from: Date().addingTimeInterval(-3600), to: Date(), label: "last hour")
    #expect(t.isRunning)
    #expect(t.running!.duration() < 5)
    #expect(t.sessions.count == 2)
    #expect(abs(t.sessions[0].duration() - 3600) < 5)
}

@MainActor @Test func pickingTagEarlyRelabelsRunningSession() {
    let t = tracker([Session(start: Date().addingTimeInterval(-120), tag: "A")])
    t.selectTag("B")
    #expect(t.sessions.count == 1)
    #expect(t.running?.tag == "B")
    #expect(t.tags == ["A", "B"])
}

@MainActor @Test func switchingTagLaterSplitsAndIsUndoable() {
    let t = tracker([Session(start: Date().addingTimeInterval(-3600), tag: "A")])
    t.selectTag("B")
    #expect(t.sessions.count == 2)
    #expect(t.sessions[0].tag == "A" && t.sessions[0].end != nil)
    #expect(t.running?.tag == "B")
    #expect(t.canUndo)
    t.undo()
    #expect(t.sessions.count == 1 && t.running?.tag == "A")
}

@MainActor @Test func tagsKeepStableOrderAndMatchCase() {
    let t = tracker([s("2026-11-20T09:00", "2026-11-20T10:00", "Uni"), s("2026-11-21T09:00", "2026-11-21T10:00", "Client")])
    #expect(t.tags == ["Uni", "Client"])
    t.selectTag("client")          // case-insensitive reuse, no duplicate
    #expect(t.tags == ["Uni", "Client"])
    #expect(t.selectedTag == "Client")
    t.selectTag("Gym")             // new tags stick around even before a session uses them
    t.selectTag("Uni")
    #expect(t.tags == ["Uni", "Client", "Gym"])
}

@MainActor @Test func renameAndRemoveTags() {
    let t = tracker([s("2026-11-20T09:00", "2026-11-20T10:00", "Uni"), s("2026-11-21T09:00", "2026-11-21T10:00", "Client")])
    t.renameTag("Uni", to: "University")
    #expect(t.sessions[0].tag == "University")
    #expect(t.tags == ["University", "Client"])
    t.renameTag("University", to: "client")   // merges into existing tag
    #expect(t.tags == ["Client"])
    #expect(t.sessions.allSatisfy { $0.tag == "Client" })
    t.removeTag("Client")
    #expect(t.tags.isEmpty)
    #expect(t.sessions[0].tag == "Client")    // history keeps its labels
}

@MainActor @Test func resumeNeverOverlapsPreviousSession() {
    let now = Date()
    let t = tracker([Session(start: now.addingTimeInterval(-600), tag: "A")])
    t.autoPause(at: now.addingTimeInterval(-60))
    t.resume(at: now.addingTimeInterval(-300))  // asked to start before the last session ended
    #expect(t.running!.start == t.sessions[0].end)
}

@MainActor @Test func shiftStartNeverOverlaps() {
    let now = Date()
    let t = tracker([Session(start: now.addingTimeInterval(-1200), end: now.addingTimeInterval(-600)),
                     Session(start: now.addingTimeInterval(-300))])
    t.shiftStart(minutes: 30)
    #expect(t.running!.start == t.sessions[0].end)
}
