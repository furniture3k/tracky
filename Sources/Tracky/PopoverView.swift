import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var idle: IdleMonitor
    @ObservedObject var prefs: Prefs
    var openStats: () -> Void

    @ViewState private var addingTag = false
    @ViewState private var newTag = ""
    @ViewState private var showSettings = false
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @FocusState private var tagFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            timer
            startStop
            tags
            Divider().opacity(0.6)
            glance
            if showSettings {
                Divider().opacity(0.6)
                settings.transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider().opacity(0.6)
            footer
        }
        .padding(18)
        .frame(width: 300)
        .overlay(alignment: .bottom) { UndoToast(tracker: tracker).padding(.bottom, 8) }
        .animation(.snappy(duration: 0.22), value: showSettings)
        .animation(.snappy(duration: 0.22), value: tracker.isRunning)
        .animation(.snappy(duration: 0.22), value: tracker.undoMessage)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 8) {
            BrandMark(size: 20)
            Text("Tracky").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape").font(.system(size: 13))
                    .foregroundStyle(showSettings ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(tracker.running.map { Stats.clock($0.duration(now: ctx.date)) } ?? "0:00:00")
                    .font(.system(size: 40, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(tracker.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(status).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if let r = tracker.running {
                        Text("since \(r.start.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        if let r = tracker.running { return r.tag.isEmpty ? Brand.accent : Brand.color(for: r.tag) }
        return tracker.isPaused ? .yellow : Color.gray.opacity(0.4)
    }

    private var status: String {
        if let r = tracker.running { return r.tag.isEmpty ? "Tracking" : r.tag }
        if tracker.isPaused { return idle.autoResume ? "Paused · resumes when you're back" : "Paused while idle" }
        return "Not tracking"
    }

    private var startStop: some View {
        VStack(spacing: 8) {
            Button(action: tracker.toggle) {
                HStack(spacing: 8) {
                    Image(systemName: tracker.isRunning ? "stop.fill" : "play.fill").font(.system(size: 12))
                    Text(tracker.isRunning ? "Stop" : (tracker.isPaused ? "Resume" : "Start"))
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(tracker.isRunning ? Color.primary : Color.white)
                .background {
                    if tracker.isRunning {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.gradient)
                            .shadow(color: Brand.accent.opacity(0.35), radius: 6, y: 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)

            if tracker.isRunning {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(.tertiary)
                        .help("Started earlier? Move the start time back")
                    mini("−5m") { tracker.shiftStart(minutes: 5) }
                    mini("−15m") { tracker.shiftStart(minutes: 15) }
                    mini("−30m") { tracker.shiftStart(minutes: 30) }
                    Spacer()
                    mini("Discard") { tracker.discardRunning() }.help("Throw away this session")
                }
            }
        }
    }

    private func mini(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(.quaternary))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tags

    private var tags: some View {
        FlowLayout(spacing: 6) {
            chip("No tag", color: nil, selected: tracker.selectedTag.isEmpty) { tracker.selectTag("") }
            ForEach(tracker.recentTags, id: \.self) { t in
                chip(t, color: Brand.color(for: t), selected: tracker.selectedTag == t) { tracker.selectTag(t) }
            }
            if !tracker.selectedTag.isEmpty && !tracker.recentTags.contains(tracker.selectedTag) {
                chip(tracker.selectedTag, color: Brand.color(for: tracker.selectedTag), selected: true) {}
            }
            if addingTag {
                TextField("New tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .frame(width: 90)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Brand.accent.opacity(0.6)))
                    .focused($tagFieldFocused)
                    .onSubmit {
                        let t = newTag.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { tracker.selectTag(t) }
                        newTag = ""; addingTag = false
                    }
                    .onExitCommand { newTag = ""; addingTag = false }
            } else {
                Button { addingTag = true; tagFieldFocused = true } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 22)
                        .background(Capsule().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("New tag")
            }
        }
    }

    private func chip(_ label: String, color: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color { Circle().fill(selected ? .white : color).frame(width: 6, height: 6) }
                Text(label).font(.callout)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(Capsule().fill(selected ? AnyShapeStyle(color ?? Color.gray) : AnyShapeStyle(.quaternary)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Today / this week

    private var glance: some View {
        TimelineView(.everyMinute) { ctx in
            let cal = Stats.calendar
            let now = ctx.date
            let wk = Stats.weekStart(now, cal: cal)
            let days = Stats.dayTotals(tracker.sessions.filter { ($0.end ?? now) > wk }, from: wk, to: now, cal: cal)
            let today = days[cal.startOfDay(for: now)] ?? 0
            let week = days.values.reduce(0, +)
            let todayIdx = Stats.weekdayIndex(now, cal: cal)
            let values = (0..<7).map { days[cal.date(byAdding: .day, value: $0, to: wk)!] ?? 0 }
            let peak = max(values.max() ?? 0, 3600)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 16) {
                    stat("Today", today)
                    stat("This week", week)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<7, id: \.self) { i in
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(i == todayIdx ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.tertiary))
                                    .frame(width: 9, height: max(3, 32 * values[i] / peak))
                                Text(["M", "T", "W", "T", "F", "S", "S"][i])
                                    .font(.system(size: 8, weight: .semibold))
                                    .fixedSize()
                                    .frame(width: 12)
                                    .foregroundStyle(i == todayIdx ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            }
                            .help(Stats.format(values[i]))
                        }
                    }
                }
                if prefs.weeklyGoal > 0 {
                    let goal = Double(prefs.weeklyGoal) * 3600
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Weekly goal").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(week >= goal ? "Done 🎉" : "\(Stats.format(goal - week)) to go")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        GoalBar(progress: week / goal)
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Stats.format(seconds)).font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
        }
        .fixedSize()
    }

    // MARK: Settings + footer

    private var settings: some View {
        VStack(alignment: .leading, spacing: 9) {
            row("Auto-pause when idle") {
                Picker("", selection: $idle.minutes) {
                    ForEach(IdleMonitor.choices, id: \.self) { m in Text(m == 0 ? "Off" : "After \(m) min").tag(m) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            row("Resume when I'm back") { Toggle("", isOn: $idle.autoResume).labelsHidden().disabled(!idle.enabled) }
            row("Menu bar shows") {
                Picker("", selection: $prefs.barMode) {
                    ForEach(Prefs.BarMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            row("Weekly goal") {
                HStack(spacing: 6) {
                    Text(prefs.weeklyGoal == 0 ? "Off" : "\(prefs.weeklyGoal)h")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Stepper("", value: $prefs.weeklyGoal, in: 0...100, step: 5).labelsHidden()
                }
            }
            row("Launch at login") {
                Toggle("", isOn: $launchAtLogin).labelsHidden()
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
        }
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(label); Spacer(); control() }.frame(minHeight: 20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: openStats) { Label("Stats", systemImage: "chart.bar.xaxis") }
                .keyboardShortcut("s", modifiers: .command)
            Spacer()
            Text("⌥⌘T").font(.caption.monospaced()).foregroundStyle(.tertiary)
                .help("Start/stop from anywhere. Right-clicking the menu bar icon works too.")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

struct GoalBar: View {
    let progress: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Brand.gradient).frame(width: max(height, g.size.width * min(progress, 1)))
            }
        }
        .frame(height: height)
    }
}

/// Minimal wrapping layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            row = max(row, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
