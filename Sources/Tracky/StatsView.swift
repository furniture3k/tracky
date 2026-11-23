import Charts
import SwiftUI

struct StatsView: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var prefs: Prefs
    @ViewState private var tab = 0
    @ViewState private var confirm: DeleteScope?
    @AppStorage("statsRange") private var range = 12

    enum DeleteScope: String, Identifiable {
        case hour = "in the last hour", today = "today", week = "this week"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            if tab == 0 {
                TimelineView(.everyMinute) { ctx in
                    Overview(tracker: tracker,
                             report: Report(sessions: tracker.sessions, rangeWeeks: range, now: ctx.date),
                             goal: Double(prefs.weeklyGoal) * 3600, now: ctx.date)
                }
                .transition(.opacity)
            } else {
                HistoryView(tracker: tracker)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: tab)
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { UndoToast(tracker: tracker).padding(.bottom, 18) }
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
                    Text(rangeLabel)
                }
                .fixedSize()
                .help("Range used for averages and breakdowns")
            }
            Menu {
                Button("Delete last hour") { confirm = .hour }
                Button("Delete today") { confirm = .today }
                Button("Delete this week") { confirm = .week }
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
        case 4: "Last 4 weeks"
        case 12: "Last 12 weeks"
        case 52: "Last year"
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
                VStack(spacing: 14) {
                    hero
                    figures
                    card("Weekly hours", trailing: legend) { weeklyChart }
                    HStack(alignment: .top, spacing: 14) {
                        weekBrowser
                        card("Where your time goes") { tagList }.frame(width: 320)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        card("Average by weekday") { weekdayChart }
                        card("When you work") { heatmap }
                    }
                    card("Notes") { insights }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            BrandMark(size: 56)
            Text("Nothing tracked yet").font(.title2.weight(.semibold))
            Text("Press ⌥⌘T, or right-click the menu bar icon, to start your first session.")
                .foregroundStyle(.secondary)
            Button("Start tracking") { tracker.toggle() }
                .buttonStyle(.borderedProminent)
                .tint(Brand.signal)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Hero

    private var hero: some View {
        let delta = report.paceAverage > 60 ? (report.thisWeek - report.paceAverage) / report.paceAverage : nil
        return HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This week").font(.callout).foregroundStyle(.secondary)
                Text(Stats.format(report.thisWeek))
                    .font(.system(size: 56, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Group {
                    if let delta {
                        (Text(delta >= 0 ? "▲ " : "▼ ").foregroundStyle(delta >= 0 ? Color.green : Brand.signal)
                         + Text("\(Int(abs(delta * 100).rounded()))% \(delta >= 0 ? "ahead of" : "behind") your usual \(Stats.format(report.paceAverage)) by \(now.formatted(.dateTime.weekday(.wide)))"))
                    } else if report.completedWeeks == 0 {
                        Text("Averages appear after your first full week")
                    } else {
                        Text("Usually \(Stats.format(report.weeklyAverage)) a week")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if goal > 0 {
                    HStack(spacing: 10) {
                        GoalBar(progress: report.thisWeek / goal, height: 4).frame(width: 220)
                        Text(report.thisWeek >= goal ? "Goal reached" : "\(Int(report.thisWeek / goal * 100))% of \(Stats.format(goal)) goal")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            heroBars
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
        .background(Surface())
    }

    private var heroBars: some View {
        let peak = max(report.thisWeekByDay.max() ?? 0, 3600)
        let today = Stats.weekdayIndex(now)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 5) {
                    Text(report.thisWeekByDay[i] >= 60 ? Stats.format(report.thisWeekByDay[i]) : "")
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary).fixedSize()
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i == today ? Brand.signal : (i < today ? Color.primary.opacity(0.55) : Brand.muted))
                        .frame(width: 18, height: max(3, 70 * report.thisWeekByDay[i] / peak))
                    Text(Self.dayNames[i].prefix(1)).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(i == today ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                .frame(width: 34)
            }
        }
    }

    /// Four key numbers in one strip, separated by hairlines.
    private var figures: some View {
        HStack(spacing: 0) {
            figure("Weekly average", report.completedWeeks > 0 ? Stats.format(report.weeklyAverage) : "—",
                   "over \(report.completedWeeks) full week\(report.completedWeeks == 1 ? "" : "s")")
            divider
            figure("Per working day", Stats.format(report.perWorkingDay), "\(report.activeDays) days with time")
            divider
            figure("Average session", Stats.format(report.averageSession), "\(report.sessionCount) sessions")
            divider
            figure("Streak", "\(report.streak) day\(report.streak == 1 ? "" : "s")", "today \(Stats.format(report.today))")
        }
        .padding(.vertical, 16)
        .background(Surface())
    }

    private var divider: some View { Brand.hairline.frame(width: 1).padding(.vertical, 2) }

    private func figure(_ title: String, _ value: String, _ foot: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold).monospacedDigit())
            Text(foot).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
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
        HStack(spacing: 14) {
            legendItem(Color.primary.opacity(0.35), "Week", solid: true)
            legendItem(Color.primary.opacity(0.6), "4-week average", solid: false)
            if goal > 0 { legendItem(Brand.signal, "Goal", solid: false) }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func legendItem(_ c: Color, _ s: String, solid: Bool) -> some View {
        HStack(spacing: 5) {
            if solid {
                RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 8, height: 8)
            } else {
                Rectangle().fill(c).frame(width: 12, height: 1.5)
            }
            Text(s)
        }
    }

    // MARK: Charts

    private var weeklyChart: some View {
        let selected = selectedWeek.map { Stats.weekStart($0) }
        let sel = report.weeks.first { $0.start == selected }
        return Chart {
            ForEach(report.weeks) { w in
                BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("Hours", w.total / 3600))
                    .foregroundStyle(barColor(w, selected: sel))
                    .cornerRadius(2)
            }
            ForEach(report.weeks) { w in
                LineMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("Average", w.rolling / 3600))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.25))
            }
            if goal > 0 {
                RuleMark(y: .value("Goal", goal / 3600))
                    .foregroundStyle(Brand.signal)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let sel {
                RuleMark(x: .value("Week", sel.start, unit: .weekOfYear))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Week of \(sel.start.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(Stats.format(sel.total)).font(.callout.weight(.semibold).monospacedDigit())
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Brand.hairline))
                    }
            }
        }
        .chartXSelection(value: $selectedWeek)
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Brand.hairline)
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

    private func barColor(_ w: Report.Week, selected: Report.Week?) -> Color {
        if let selected, selected.start == w.start { return Brand.signal }
        if w.start == report.thisWeekStart { return Brand.signal.opacity(selected == nil ? 1 : 0.5) }
        return Color.primary.opacity(selected == nil ? 0.28 : 0.16)
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
            Text(Stats.format(total)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Button { withAnimation(.tracky) { weekOffset -= 1 } } label: { Image(systemName: "chevron.left") }
                    .help("Previous week")
                Button { withAnimation(.tracky) { weekOffset = min(0, weekOffset + 1) } } label: { Image(systemName: "chevron.right") }
                    .disabled(weekOffset == 0)
                    .help("Next week")
            }
            .buttonStyle(.borderless)
        }) {
            Chart(data) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Hours", d.seconds / 3600))
                    .foregroundStyle(by: .value("Tag", d.tag))
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale(domain: tags, range: tags.map(Brand.color(for:)))
            .chartXScale(domain: start...end)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true) }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Brand.hairline)
                    AxisValueLabel { if let h = v.as(Double.self) { Text(Stats.axisHours(h)) } }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 180)
        }
    }

    private var tagList: some View {
        VStack(spacing: 11) {
            ForEach(report.byTag.prefix(7)) { t in
                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Brand.color(for: t.tag)).frame(width: 8, height: 8)
                        Text(t.tag).lineLimit(1)
                        Spacer()
                        Text(Stats.format(t.seconds)).monospacedDigit()
                        Text("\(Int((t.share * 100).rounded()))%").monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    }
                    .font(.callout)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Brand.hairline)
                            Rectangle().fill(Brand.color(for: t.tag)).frame(width: max(2, g.size.width * t.share))
                        }
                    }
                    .frame(height: 3)
                }
            }
            if report.byTag.count > 7 {
                Text("and \(report.byTag.count - 7) more").font(.caption).foregroundStyle(.tertiary)
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
                .foregroundStyle(i == top ? Brand.signal : Color.primary.opacity(0.22))
                .cornerRadius(2)
                .annotation(position: .top) {
                    if report.weekday[i] > 0 {
                        Text(Stats.format(report.weekday[i] * 3600)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
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
                HStack(spacing: 2) {
                    Text(Self.dayNames[d]).font(.caption2).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                    ForEach(0..<24, id: \.self) { h in
                        let v = report.heat[d][h] / peak
                        Rectangle()
                            .fill(v > 0 ? Brand.signal.opacity(0.12 + 0.88 * v) : Color.primary.opacity(0.05))
                            .frame(maxWidth: .infinity)
                            .frame(height: 17)
                            .help("\(Self.dayNames[d]) \(h):00 · \(Stats.format(report.heat[d][h])) total")
                    }
                }
            }
            HStack(spacing: 0) {
                Spacer().frame(width: 32)
                ForEach(["12am", "6am", "12pm", "6pm"], id: \.self) { l in
                    Text(l).font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)
        }
        .frame(height: 170)
    }

    // MARK: Notes (plain definition list, no icon tiles)

    private var insights: some View {
        let items: [(String, String)] = [
            report.topWeekday.map { ("Most productive day", Stats.calendar.weekdaySymbols[($0 + 1) % 7] + "s") },
            report.peakHour.map { ("Busiest hour", hourRange($0)) },
            report.bestWeek.map { ("Best week", "\(Stats.format($0.total)), week of \($0.start.formatted(.dateTime.day().month(.abbreviated)))") },
            report.longestSession > 0 ? ("Longest session", Stats.format(report.longestSession)) : nil,
            ("This month", Stats.format(report.monthTotal)),
            ("Total in range", Stats.format(report.rangeTotal)),
        ].compactMap { $0 }
        let half = (items.count + 1) / 2
        return HStack(alignment: .top, spacing: 28) {
            ForEach([Array(items.prefix(half)), Array(items.dropFirst(half))], id: \.first?.0) { column in
                VStack(spacing: 0) {
                    ForEach(column, id: \.0) { label, value in
                        HStack {
                            Text(label).foregroundStyle(.secondary)
                            Spacer()
                            Text(value).monospacedDigit()
                        }
                        .font(.callout)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Brand.hairline.frame(height: 1) }
                    }
                }
            }
        }
    }

    private func hourRange(_ h: Int) -> String {
        func f(_ h: Int) -> String { let x = h % 12 == 0 ? 12 : h % 12; return "\(x)\(h % 24 < 12 ? "am" : "pm")" }
        return "\(f(h))–\(f(h + 1))"
    }
}

/// Flat card surface: plain fill and a hairline. No shadow.
struct Surface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.hairline))
    }
}
