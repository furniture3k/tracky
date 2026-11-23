import ServiceManagement
import SwiftUI

/// One spring used everywhere so motion feels consistent.
extension Animation {
    static let tracky = Animation.spring(response: 0.34, dampingFraction: 0.88)
}

struct PopoverView: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var idle: IdleMonitor
    @ObservedObject var prefs: Prefs
    var openStats: () -> Void

    @ViewState private var showSettings = false
    @ViewState private var addingTag = false
    @ViewState private var newTag = ""
    @ViewState private var renaming: String?
    @ViewState private var renameText = ""
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @FocusState private var focusedField: Field?

    private enum Field { case newTag, rename }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            ZStack(alignment: .topLeading) {
                main
                    .offset(x: showSettings ? -24 : 0)
                    .opacity(showSettings ? 0 : 1)
                    .allowsHitTesting(!showSettings)
                if showSettings {
                    settings
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.asymmetric(insertion: .offset(x: 28).combined(with: .opacity),
                                                removal: .offset(x: 28).combined(with: .opacity)))
                }
            }
        }
        .padding(18)
        .frame(width: 300)
        .overlay(alignment: .bottom) { UndoToast(tracker: tracker).padding(.bottom, 10) }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            BrandMark(size: 20)
            Text(showSettings ? "Settings" : "Tracky")
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.opacity)
            Spacer()
            Button {
                withAnimation(.tracky) { showSettings.toggle() }
            } label: {
                ZStack {
                    Image(systemName: "gearshape").opacity(showSettings ? 0 : 1)
                    Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.signal)
                        .opacity(showSettings ? 1 : 0)
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, minHeight: 20, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help(showSettings ? "Back" : "Settings (⌘,)")
        }
    }

    // MARK: Main page

    private var main: some View {
        VStack(alignment: .leading, spacing: 14) {
            timer
            startStop
            tags
            Brand.hairline.frame(height: 1)
            glance
            Brand.hairline.frame(height: 1)
            footer
        }
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(tracker.running.map { Stats.clock($0.duration(now: ctx.date)) } ?? "0:00:00")
                    .font(.system(size: 40, weight: .light).monospacedDigit())
                    .foregroundStyle(tracker.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
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
        if let r = tracker.running { return r.tag.isEmpty ? Brand.signal : Brand.color(for: r.tag) }
        return tracker.isPaused ? Color.orange : Color.gray.opacity(0.4)
    }

    private var status: String {
        if let r = tracker.running { return r.tag.isEmpty ? "Tracking" : r.tag }
        if tracker.isPaused { return idle.autoResume ? "Paused · resumes when you're back" : "Paused while idle" }
        return "Not tracking"
    }

    private var startStop: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.tracky) { tracker.toggle() } }) {
                HStack(spacing: 7) {
                    Image(systemName: tracker.isRunning ? "stop.fill" : "play.fill").font(.system(size: 11))
                    Text(tracker.isRunning ? "Stop" : (tracker.isPaused ? "Resume" : "Start"))
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(tracker.isRunning ? Color.primary : Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tracker.isRunning ? AnyShapeStyle(Color.primary.opacity(0.08)) : AnyShapeStyle(Brand.signal))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tracker.isRunning ? Brand.hairline : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut(.return, modifiers: .command)

            // Always occupies the same height, so the panel never jumps when you start or stop.
            ZStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text("Started earlier?").font(.caption).foregroundStyle(.tertiary).fixedSize()
                    mini("−5m") { tracker.shiftStart(minutes: 5) }
                    mini("−15m") { tracker.shiftStart(minutes: 15) }
                    mini("−30m") { tracker.shiftStart(minutes: 30) }
                    Spacer(minLength: 4)
                    mini("Discard") { tracker.discardRunning() }.help("Throw away this session (undoable)")
                }
                .opacity(tracker.isRunning ? 1 : 0)
                .allowsHitTesting(tracker.isRunning)

                Text("⌥⌘T or right-click the menu bar icon to start and stop")
                    .font(.caption).foregroundStyle(.tertiary)
                    .opacity(tracker.isRunning ? 0 : 1)
            }
            .frame(height: 20)
        }
        .animation(.tracky, value: tracker.isRunning)
    }

    private func mini(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium)).fixedSize()
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Brand.muted))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Tags

    private var tags: some View {
        FlowLayout(spacing: 6) {
            chip("No tag", color: nil, selected: tracker.selectedTag.isEmpty) { tracker.selectTag("") }
            ForEach(tracker.tags, id: \.self) { t in
                if renaming == t {
                    inlineField($renameText, field: .rename, placeholder: t) {
                        tracker.renameTag(t, to: renameText)
                        renaming = nil
                    } cancel: { renameText = ""; renaming = nil }
                } else {
                    chip(t, color: Brand.color(for: t), selected: tracker.selectedTag == t) { tracker.selectTag(t) }
                        .contextMenu {
                            Button("Rename…") { renameText = t; renaming = t; focus(.rename) }
                            Button("Move Left") { tracker.moveTag(t, by: -1) }
                                .disabled(tracker.tags.first == t)
                            Button("Move Right") { tracker.moveTag(t, by: 1) }
                                .disabled(tracker.tags.last == t)
                            Divider()
                            Button("Remove from List") { tracker.removeTag(t) }
                        }
                }
            }
            if addingTag {
                inlineField($newTag, field: .newTag, placeholder: "New tag") {
                    let t = newTag.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { tracker.selectTag(t) }
                    newTag = ""; addingTag = false
                } cancel: { newTag = ""; addingTag = false }
            } else {
                Button { addingTag = true; focus(.newTag) } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        .frame(width: 26, height: 22)
                        .background(Capsule().strokeBorder(Brand.muted, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .help("New tag · right-click a tag to rename, reorder or remove it")
            }
        }
        .animation(.tracky, value: tracker.tags)
        .animation(.tracky, value: tracker.selectedTag)
    }

    /// TextFields can't take focus in the same update that creates them, so focus on the next turn.
    private func focus(_ f: Field) {
        DispatchQueue.main.async { focusedField = f }
    }

    private func inlineField(_ text: Binding<String>, field: Field, placeholder: String,
                             submit: @escaping () -> Void, cancel: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.callout)
            .frame(width: 96)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().strokeBorder(Brand.signal.opacity(0.7)))
            .focused($focusedField, equals: field)
            .onSubmit(submit)
            .onExitCommand(perform: cancel)
            .onChange(of: focusedField) { old, new in
                // Clicking elsewhere commits a new tag / rename, like Finder.
                if old == field && new != field { submit() }
            }
    }

    private func chip(_ label: String, color: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color { Circle().fill(selected ? Color.white : color).frame(width: 6, height: 6) }
                Text(label).font(.callout).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 3)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(Capsule().fill(selected ? (color ?? Color.primary.opacity(0.75)) : .clear))
            .overlay(Capsule().strokeBorder(selected ? .clear : Brand.muted))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
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
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(i == todayIdx ? Brand.signal : Brand.muted)
                                    .frame(width: 9, height: max(2, 32 * values[i] / peak))
                                Text(["M", "T", "W", "T", "F", "S", "S"][i])
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(i == todayIdx ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                                    .fixedSize()
                                    .frame(width: 12)
                            }
                            .help(Stats.format(values[i]))
                        }
                    }
                }
                if prefs.weeklyGoal > 0 {
                    let goal = Double(prefs.weeklyGoal) * 3600
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Weekly goal \(prefs.weeklyGoal)h").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(week >= goal ? "Reached" : "\(Stats.format(goal - week)) to go")
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
            Text(Stats.format(seconds)).font(.system(size: 17, weight: .semibold).monospacedDigit())
        }
        .fixedSize()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: openStats) { Label("Stats", systemImage: "chart.bar") }
                .keyboardShortcut("s", modifiers: .command)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    // MARK: Settings page

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Tracking")
            row("Auto-pause when idle") {
                Picker("", selection: $idle.minutes) {
                    ForEach(IdleMonitor.choices, id: \.self) { m in Text(m == 0 ? "Off" : "After \(m) min").tag(m) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            row("Resume when I'm back") {
                Toggle("", isOn: $idle.autoResume).labelsHidden().disabled(!idle.enabled)
            }
            row("Weekly goal") {
                HStack(spacing: 6) {
                    Text(prefs.weeklyGoal == 0 ? "Off" : "\(prefs.weeklyGoal)h")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Stepper("", value: $prefs.weeklyGoal, in: 0...100, step: 5).labelsHidden()
                }
            }
            section("Menu bar").padding(.top, 10)
            row("Show") {
                Picker("", selection: $prefs.barMode) {
                    ForEach(Prefs.BarMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            row("Launch at login") {
                Toggle("", isOn: $launchAtLogin).labelsHidden()
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
            Text("Shortcuts: ⌥⌘T start/stop anywhere · right-click icon to start/stop · ⌘S stats · ⌘, settings")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(label); Spacer(); control() }
            .frame(minHeight: 30)
            .overlay(alignment: .bottom) { Brand.hairline.frame(height: 1) }
    }
}

/// Subtle press feedback for custom buttons.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GoalBar: View {
    let progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.hairline)
                Capsule().fill(Brand.signal).frame(width: max(height, g.size.width * min(progress, 1)))
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
