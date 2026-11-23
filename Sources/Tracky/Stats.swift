import Foundation

/// Pure aggregation over sessions. Nothing here is computed until a view asks for it.
enum Stats {
    /// Monday-first calendar in the user's time zone.
    static let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    /// Walks every session clipped to [from, to), cut at `unit` boundaries (day or hour).
    static func slices(_ sessions: [Session], from: Date = .distantPast, to: Date,
                       unit: Calendar.Component, cal: Calendar = calendar,
                       _ body: (_ bucket: Date, _ tag: String, _ seconds: Double) -> Void) {
        for s in sessions {
            var a = max(s.start, from)
            let b = min(s.end ?? to, to)
            while a < b {
                guard let iv = cal.dateInterval(of: unit, for: a) else { break }
                let e = min(iv.end, b)
                body(iv.start, s.tag, e.timeIntervalSince(a))
                a = e
            }
        }
    }

    static func dayTotals(_ sessions: [Session], from: Date = .distantPast, to: Date,
                          cal: Calendar = calendar) -> [Date: Double] {
        var out: [Date: Double] = [:]
        slices(sessions, from: from, to: to, unit: .day, cal: cal) { d, _, s in out[d, default: 0] += s }
        return out
    }

    static func weekStart(_ d: Date, cal: Calendar = calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: d)!.start
    }

    /// 0 = Monday … 6 = Sunday.
    static func weekdayIndex(_ d: Date, cal: Calendar = calendar) -> Int {
        (cal.component(.weekday, from: d) + 5) % 7
    }

    /// Consecutive days with any tracked time, counting back from today (or yesterday if today is empty).
    static func streak(_ sessions: [Session], now: Date, cal: Calendar = calendar) -> Int {
        let days = dayTotals(sessions, to: now, cal: cal)
        var day = cal.startOfDay(for: now)
        if (days[day] ?? 0) <= 0 { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while (days[day] ?? 0) > 0 {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    static func format(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// Axis label for an hour value: "2h", "1.5h", "30m".
    static func axisHours(_ h: Double) -> String {
        if h > 0 && h < 1 { return "\(Int((h * 60).rounded()))m" }
        return h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h)
    }

    static func clock(_ seconds: Double) -> String {
        let t = Int(seconds)
        return String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
    }
}

/// Everything the stats window shows, for one averaging range.
struct Report {
    struct Week: Identifiable { var id: Date { start }; let start: Date; let total: Double; let rolling: Double }
    struct DayTag: Identifiable { var id: String { "\(day.timeIntervalSince1970)-\(tag)" }; let day: Date; let tag: String; let seconds: Double }
    struct TagTotal: Identifiable { var id: String { tag }; let tag: String; let seconds: Double; let share: Double }

    /// Number of completed weeks to average over; 0 = all time.
    let rangeWeeks: Int
    let completedWeeks: Int
    let thisWeek: Double
    let today: Double
    let todaySessions: Int
    let weeklyAverage: Double
    /// Average tracked by this same point in the week (e.g. "by Tuesday 3pm") over completed weeks.
    let paceAverage: Double
    let perWorkingDay: Double
    let averageSession: Double
    let sessionCount: Int
    let streak: Int
    let weeks: [Week]
    let thisWeekStart: Date
    /// Seconds per day of the current week, Monday first.
    let thisWeekByDay: [Double]
    let byTag: [TagTotal]
    /// Average hours per weekday (Mon…Sun) across completed weeks in range.
    let weekday: [Double]
    /// Total seconds per [weekday][hour] across the range.
    let heat: [[Double]]
    let isEmpty: Bool
    // Insights
    let rangeTotal: Double
    let activeDays: Int
    let bestWeek: Week?
    let topWeekday: Int?
    let peakHour: Int?
    let longestSession: Double
    let monthTotal: Double

    init(sessions: [Session], rangeWeeks: Int, now: Date = Date(), cal: Calendar = Stats.calendar) {
        self.rangeWeeks = rangeWeeks
        isEmpty = sessions.isEmpty
        let curWeek = Stats.weekStart(now, cal: cal)
        thisWeekStart = curWeek
        let firstWeek = sessions.first.map { Stats.weekStart($0.start, cal: cal) } ?? curWeek

        // Window of completed weeks, clipped to when your data starts so averages aren't diluted.
        var windowStart = rangeWeeks > 0 ? cal.date(byAdding: .weekOfYear, value: -rangeWeeks, to: curWeek)! : firstWeek
        windowStart = max(windowStart, firstWeek)
        let completed = max(0, cal.dateComponents([.weekOfYear], from: windowStart, to: curWeek).weekOfYear ?? 0)
        completedWeeks = completed

        // Per-day totals over the window plus the current week.
        let days = Stats.dayTotals(sessions, from: windowStart, to: now, cal: cal)
        let todayStart = cal.startOfDay(for: now)
        today = days[todayStart] ?? 0
        todaySessions = sessions.reduce(0) { $0 + (($1.end ?? now) > todayStart ? 1 : 0) }
        thisWeek = days.filter { $0.key >= curWeek }.values.reduce(0, +)
        thisWeekByDay = (0..<7).map { days[cal.date(byAdding: .day, value: $0, to: curWeek)!] ?? 0 }
        let completedTotal = days.filter { $0.key < curWeek }.values.reduce(0, +)
        weeklyAverage = completed > 0 ? completedTotal / Double(completed) : 0
        if completed > 0 {
            let offset = now.timeIntervalSince(curWeek)
            var paceSum = 0.0
            for k in 1...completed {
                let ws = cal.date(byAdding: .weekOfYear, value: -k, to: curWeek)!
                for s in sessions where s.start < ws.addingTimeInterval(offset) && (s.end ?? now) > ws {
                    paceSum += min(s.end ?? now, ws.addingTimeInterval(offset)).timeIntervalSince(max(s.start, ws))
                }
            }
            paceAverage = paceSum / Double(completed)
        } else {
            paceAverage = 0
        }

        let worked = days.values.filter { $0 > 0 }
        perWorkingDay = worked.isEmpty ? 0 : worked.reduce(0, +) / Double(worked.count)
        activeDays = worked.count
        rangeTotal = worked.reduce(0, +)

        let inRange = sessions.filter { ($0.end ?? now) > windowStart }
        sessionCount = inRange.count
        averageSession = inRange.isEmpty ? 0 : inRange.reduce(0) { $0 + $1.duration(now: now) } / Double(inRange.count)
        longestSession = inRange.map { $0.duration(now: now) }.max() ?? 0

        streak = Stats.streak(sessions, now: now, cal: cal)

        // Weekly trend with a 4-week trailing average.
        var weekTotals: [Date: Double] = [:]
        for (d, s) in days { weekTotals[Stats.weekStart(d, cal: cal), default: 0] += s }
        var ws: [Week] = []
        var w = windowStart
        var totals: [Double] = []
        while w <= curWeek {
            let t = weekTotals[w] ?? 0
            totals.append(t)
            let tail = totals.suffix(4)
            ws.append(Week(start: w, total: t, rolling: tail.reduce(0, +) / Double(tail.count)))
            w = cal.date(byAdding: .weekOfYear, value: 1, to: w)!
        }
        weeks = ws
        bestWeek = ws.filter { $0.total > 0 }.max { $0.total < $1.total }

        // By tag, weekday and hour-of-day over the whole range.
        var tagTotals: [String: Double] = [:]
        var wd = [Double](repeating: 0, count: 7)
        var heat = [[Double]](repeating: [Double](repeating: 0, count: 24), count: 7)
        Stats.slices(sessions, from: windowStart, to: now, unit: .hour, cal: cal) { h, t, s in
            tagTotals[t.isEmpty ? "Untagged" : t, default: 0] += s
            let i = Stats.weekdayIndex(h, cal: cal)
            heat[i][cal.component(.hour, from: h)] += s
            if h < curWeek { wd[i] += s }
        }
        let tagSum = max(tagTotals.values.reduce(0, +), 1)
        byTag = tagTotals.map { TagTotal(tag: $0.key, seconds: $0.value, share: $0.value / tagSum) }
            .sorted { $0.seconds > $1.seconds }
        weekday = wd.map { completed > 0 ? $0 / Double(completed) / 3600 : 0 }
        self.heat = heat

        let wdMax = weekday.enumerated().max { $0.element < $1.element }
        topWeekday = (wdMax?.element ?? 0) > 0 ? wdMax?.offset : nil
        let hourSums = (0..<24).map { h in heat.reduce(0) { $0 + $1[h] } }
        let hMax = hourSums.enumerated().max { $0.element < $1.element }
        peakHour = (hMax?.element ?? 0) > 0 ? hMax?.offset : nil

        let monthStart = cal.dateInterval(of: .month, for: now)!.start
        monthTotal = Stats.dayTotals(sessions, from: monthStart, to: now, cal: cal).values.reduce(0, +)
    }

    /// Day × tag breakdown for any week (used by the week browser).
    static func breakdown(_ sessions: [Session], week: Date, now: Date, cal: Calendar = Stats.calendar) -> [DayTag] {
        let end = min(now, cal.date(byAdding: .day, value: 7, to: week)!)
        guard end > week else { return [] }
        var dayTag: [Date: [String: Double]] = [:]
        Stats.slices(sessions, from: week, to: end, unit: .day, cal: cal) { d, t, s in dayTag[d, default: [:]][t, default: 0] += s }
        return dayTag.flatMap { d, tags in tags.map { DayTag(day: d, tag: $0.key.isEmpty ? "Untagged" : $0.key, seconds: $0.value) } }
            .sorted { ($0.day, $0.tag) < ($1.day, $1.tag) }
    }
}
