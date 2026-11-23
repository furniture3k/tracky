import Charts
import SwiftUI

struct StatsView: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var prefs: Prefs
    @ViewState private var tab = 0
    @ViewState private var confirm: DeleteScope?
    @AppStorage("statsRange") private var range = 12

    enum DeleteScope: String, Identifiable {
        case hour = "the last hour", today = "today", week = "this week"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if tab == 0 {
                TimelineView(.everyMinute) { ctx in
                    Overview(tracker: tracker,
                             report: Report(sessions: tracker.sessions, rangeWeeks: range, now: ctx.date),
                             goal: Double(prefs.weeklyGoal) * 3600, now: ctx.date)
                }
            } else {
                HistoryView(tracker: tracker)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { UndoToast(tracker: tracker).padding(.bottom, 18) }
        .animation(.snappy(duration: 0.25), value: tracker.undoMessage)
        .environment(\.calendar, Stats.calendar)
        .navigationTitle("Tracky")
        .toolbar { toolbar }
        .confirmationDialog(confirm.map { "Delete everything tracked \($0.rawValue)?" } ?? "",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { scope in
            Button("Delete", role: .destructive) { delete(scope) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Sessions that cross the edge are trimmed. If you're tracking, it carries on from now. You can undo straight after.")
        }
        .background {
            // Window-level shortcuts.
            Group {
                Button("") { tab = 0 }.keyboardShortcut("1", modifiers: .command)
                Button("") { tab = 1 }.keyboardShortcut("2", modifiers: .command)
                Button("") { tracker.undo() }.keyboardShortcut("z", modifiers: .command).disabled(!tracker.canUndo)
                Button("") { StatsWindow.exportCSV(tracker.sessions) }.keyboardShortcut("e", modifiers: .command)
            }
            .opacity(0).allowsHitTesting(false)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                Text("Tracky").font(.system(size: 14, weight: .semibold))
            }
            .padding(.leading, 4)
        }
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $tab) {
                Text("Overview").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if tab == 0 {
                Menu {
                    Picker("Average over", selection: $range) {
                        Text("Last 4 weeks").tag(4)
                        Text("Last 12 weeks").tag(12)
                        Text("Last year").tag(52)
                        Text("All time").tag(0)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(rangeLabel, systemImage: "calendar")
                }
                .help("Range used for averages and breakdowns")
            }
            Menu {
                Button("Delete last hour", systemImage: "clock.arrow.circlepath") { confirm = .hour }
                Button("Delete today", systemImage: "sun.max") { confirm = .today }
                Button("Delete this week", systemImage: "calendar") { confirm = .week }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete tracked time")
            Button { StatsWindow.exportCSV(tracker.sessions) } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .help("Export all sessions as CSV (⌘E)")
        }
    }

    private var rangeLabel: String {
        switch range {
        case 4: "4 weeks"
        case 12: "12 weeks"
        case 52: "1 year"
        default: "All time"
        }
    }

    private func delete(_ scope: DeleteScope) {
        let now = Date(), cal = Stats.calendar
        switch scope {
        case .hour: tracker.removeRange(from: now.addingTimeInterval(-3600), to: now, label: "last hour")
        case .today:
            let d = cal.dateInterval(of: .day, for: now)!
            tracker.removeRange(from: d.start, to: d.end, label: "today")
        case .week:
            let w = cal.dateInterval(of: .weekOfYear, for: now)!
            tracker.removeRange(from: w.start, to: w.end, label: "this week")
        }
    }
}

// MARK: - Overview

private struct Overview: View {
    @ObservedObject var tracker: Tracker
    let report: Report
    let goal: Double
    let now: Date

    @ViewState private var selectedWeek: Date?
    @ViewState private var weekOffset = 0

    private static let dayNames: [String] = {
        let s = Stats.calendar.shortWeekdaySymbols
        return Array(s[1...] + s[..<1]) // Monday first
    }()

    var body: some View {
        if report.isEmpty {
            empty
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        hero
                        metrics.frame(width: 330)
                    }
                    card("Weekly hours", trailing: legend) { weeklyChart }
                    HStack(alignment: .top, spacing: 16) {
                        weekBrowser
                        card("Where your time goes") { tagList }.frame(width: 330)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        card("Average by weekday") { weekdayChart }
                        card("When you work") { heatmap }
                    }
                    insights
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            BrandMark(size: 64, progress: 0.75)
            Text("Nothing tracked yet").font(.title2.weight(.semibold))
            Text("Press ⌥⌘T, or right-click the menu bar icon, to start your first session.")
                .foregroundStyle(.secondary)
            Button { tracker.toggle() } label: {
                Label("Start tracking", systemImage: "play.fill")
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Brand.gradient))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Hero

    private var hero: some View {
        let delta = report.paceAverage > 60 ? (report.thisWeek - report.paceAverage) / report.paceAverage : nil
        return VStack(alignment: .leading, spacing: 10) {
            Text("THIS WEEK").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Stats.format(report.thisWeek))
                    .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                if let delta {
                    Label(String(format: "%+.0f%%", delta * 100), systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.18)))
                        .help("Compared with what you'd usually have tracked by this point in the week")
                }
            }
            Text(report.completedWeeks == 0 ? "Your averages appear after your first full week"
                 : "vs \(Stats.format(report.paceAverage)) usual by \(now.formatted(.dateTime.weekday(.wide))) · \(Stats.format(report.weeklyAverage)) avg week")
                .font(.callout).foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 4)
            if goal > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Goal \(Stats.format(goal))").font(.caption.weight(.medium))
                        Spacer()
                        Text(report.thisWeek >= goal ? "Reached 🎉" : "\(Int(report.thisWeek / goal * 100))%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.2))
                            Capsule().fill(.white).frame(width: max(6, g.size.width * min(report.thisWeek / goal, 1)))
                        }
                    }
                    .frame(height: 6)
                }
            }
            HStack(alignment: .bottom) {
                HStack(spacing: 14) {
                    Label("Today \(Stats.format(report.today))", systemImage: "sun.max.fill")
                    Label("\(report.todaySessions) session\(report.todaySessions == 1 ? "" : "s") today", systemImage: "circle.dotted")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                Spacer()
                heroBars
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Brand.gradient)
                .overlay(alignment: .topTrailing) {
                    // Decorative brand ring.
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(.white.opacity(0.13), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 170, height: 170)
                        .offset(x: 40, y: -40)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Brand.accent.opacity(0.25), radius: 14, y: 6)
        }
    }

    private var heroBars: some View {
        let peak = max(report.thisWeekByDay.max() ?? 0, 3600)
        let today = Stats.weekdayIndex(now)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(i == today ? 1 : (i < today ? 0.6 : 0.22)))
                        .frame(width: 14, height: max(4, 54 * report.thisWeekByDay[i] / peak))
                    Text(Self.dayNames[i].prefix(1)).font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(i == today ? 1 : 0.6))
                }
                .help("\(Self.dayNames[i]): \(Stats.format(report.thisWeekByDay[i]))")
            }
        }
    }

    private var metrics: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                metric("Weekly avg", report.completedWeeks > 0 ? Stats.format(report.weeklyAverage) : "—",
                       "\(report.completedWeeks) full week\(report.completedWeeks == 1 ? "" : "s")", "chart.line.uptrend.xyaxis")
                metric("Per work day", Stats.format(report.perWorkingDay), "\(report.activeDays) active days", "calendar")
            }
            GridRow {
                metric("Avg session", Stats.format(report.averageSession), "\(report.sessionCount) sessions", "timer")
                metric("Streak", "\(report.streak)d", report.streak > 0 ? "keep it going" : "start today", "flame.fill")
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ foot: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.accent)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Brand.accent.opacity(0.14)))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            Text(foot).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(14)
        .background(Surface())
    }

    // MARK: Cards

    private func card<C: View, T: View>(_ title: String, trailing: T, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                trailing
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Surface())
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        card(title, trailing: EmptyView(), content)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(Brand.accent, "Week")
            legendItem(Color.primary.opacity(0.45), "4-wk avg")
            if goal > 0 { legendItem(.green, "Goal") }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func legendItem(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 10, height: 3); Text(s) }
    }

    // MARK: Charts

    private var weeklyChart: some View {
        let selected = selectedWeek.map { Stats.weekStart($0) }
        let sel = report.weeks.first { $0.start == selected }
        return Chart {
            ForEach(report.weeks) { w in
                BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("Hours", w.total / 3600))
                    .foregroundStyle(Brand.gradient)
                    .opacity(sel == nil || sel?.start == w.start ? (w.start == report.thisWeekStart ? 0.55 : 1) : 0.35)
                    .cornerRadius(4)
            }
            ForEach(report.weeks) { w in
                LineMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("Average", w.rolling / 3600))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if goal > 0 {
                RuleMark(y: .value("Goal", goal / 3600))
                    .foregroundStyle(.green.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let sel {
                RuleMark(x: .value("Week", sel.start, unit: .weekOfYear))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text("Week of \(sel.start.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(Stats.format(sel.total)).font(.callout.weight(.semibold).monospacedDigit())
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
            }
        }
        .chartXSelection(value: $selectedWeek)
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel { if let h = v.as(Double.self) { Text(Stats.axisHours(h)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 200)
    }

    private var weekBrowser: some View {
        let cal = Stats.calendar
        let start = cal.date(byAdding: .weekOfYear, value: weekOffset, to: report.thisWeekStart)!
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        let data = Report.breakdown(tracker.sessions, week: start, now: now)
        let total = data.reduce(0) { $0 + $1.seconds }
        let tags = Array(Set(data.map(\.tag))).sorted()
        let title = weekOffset == 0 ? "This week" : weekOffset == -1 ? "Last week"
            : "Week of \(start.formatted(.dateTime.day().month(.abbreviated)))"
        return card(title, trailing: HStack(spacing: 10) {
            Text(Stats.format(total)).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                Button { weekOffset = min(0, weekOffset + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(weekOffset == 0)
            }
            .buttonStyle(.borderless)
        }) {
            Chart(data) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Hours", d.seconds / 3600))
                    .foregroundStyle(by: .value("Tag", d.tag))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: tags, range: tags.map(Brand.color(for:)))
            .chartXScale(domain: start...end)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true) }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel { if let h = v.as(Double.self) { Text(Stats.axisHours(h)) } }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 180)
        }
    }

    private var tagList: some View {
        VStack(spacing: 12) {
            ForEach(report.byTag.prefix(6)) { t in
                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        Circle().fill(Brand.color(for: t.tag)).frame(width: 8, height: 8)
                        Text(t.tag).lineLimit(1)
                        Spacer()
                        Text(Stats.format(t.seconds)).monospacedDigit()
                        Text("\(Int((t.share * 100).rounded()))%").monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    }
                    .font(.callout)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(Brand.color(for: t.tag)).frame(width: max(4, g.size.width * t.share))
                        }
                    }
                    .frame(height: 5)
                }
            }
            if report.byTag.count > 6 {
                Text("+ \(report.byTag.count - 6) more").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if report.byTag.isEmpty {
                Text("No time in this range").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 180, alignment: .top)
    }

    private var weekdayChart: some View {
        let top = report.topWeekday
        return Chart(0..<7, id: \.self) { i in
            BarMark(x: .value("Day", Self.dayNames[i]), y: .value("Hours", report.weekday[i]))
                .foregroundStyle(i == top ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.18)))
                .cornerRadius(4)
                .annotation(position: .top) {
                    if report.weekday[i] > 0 {
                        Text(String(format: "%.1f", report.weekday[i])).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks { _ in AxisValueLabel() } }
        .frame(height: 170)
    }

    private var heatmap: some View {
        let peak = max(report.heat.flatMap { $0 }.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<7, id: \.self) { d in
                HStack(spacing: 3) {
                    Text(Self.dayNames[d]).font(.caption2).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                    ForEach(0..<24, id: \.self) { h in
                        let v = report.heat[d][h] / peak
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(v > 0 ? AnyShapeStyle(Brand.accent.opacity(0.15 + 0.85 * v)) : AnyShapeStyle(.quaternary.opacity(0.5)))
                            .frame(maxWidth: .infinity)
                            .frame(height: 17)
                            .help("\(Self.dayNames[d]) \(h):00 — \(Stats.format(report.heat[d][h])) total")
                    }
                }
            }
            HStack(spacing: 0) {
                Spacer().frame(width: 33)
                ForEach(["12am", "6am", "12pm", "6pm"], id: \.self) { l in
                    Text(l).font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)
        }
        .frame(height: 170)
    }

    // MARK: Insights

    private var insights: some View {
        let items: [(String, String, String)] = [
            report.topWeekday.map { ("star.fill", "Most productive day", Stats.calendar.weekdaySymbols[($0 + 1) % 7] + "s") },
            report.peakHour.map { ("sun.horizon.fill", "Peak hour", hourRange($0)) },
            report.bestWeek.map { ("trophy.fill", "Best week", "\(Stats.format($0.total)) · \($0.start.formatted(.dateTime.day().month(.abbreviated)))") },
            report.longestSession > 0 ? ("hourglass", "Longest session", Stats.format(report.longestSession)) : nil,
            ("calendar.badge.clock", "This month", Stats.format(report.monthTotal)),
            ("sum", "Total in range", Stats.format(report.rangeTotal)),
        ].compactMap { $0 }
        return card("Insights") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(items, id: \.1) { icon, label, value in
                    HStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Brand.accent)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.accent.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                            Text(value).font(.callout.weight(.semibold).monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private func hourRange(_ h: Int) -> String {
        func f(_ h: Int) -> String { let x = h % 12 == 0 ? 12 : h % 12; return "\(x)\(h < 12 || h == 24 ? "am" : "pm")" }
        return "\(f(h))–\(f(h + 1))"
    }
}

/// Card surface that reads well in light and dark mode.
struct Surface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}
