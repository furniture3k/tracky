import SwiftUI

struct HistoryView: View {
    @ObservedObject var tracker: Tracker
    @ViewState private var editing: Session?
    @ViewState private var query = ""

    private struct Day: Identifiable { let id: Date; let sessions: [Session]; let total: Double }

    private var filtered: [Session] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return tracker.sessions }
        if q.lowercased() == "untagged" { return tracker.sessions.filter { $0.tag.isEmpty } }
        return tracker.sessions.filter { $0.tag.localizedCaseInsensitiveContains(q) }
    }

    private func days(_ list: [Session]) -> [Day] {
        let cal = Stats.calendar
        let now = Date()
        return Dictionary(grouping: list) { cal.startOfDay(for: $0.start) }
            .map { Day(id: $0.key, sessions: $0.value.sorted { $0.start > $1.start },
                       total: $0.value.reduce(0) { $0 + $1.duration(now: now) }) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        let list = filtered
        let total = list.reduce(0) { $0 + $1.duration() }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Filter by tag", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6)))
                .frame(maxWidth: 260)

                Text("\(list.count) sessions · \(Stats.format(total))")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    let now = Date()
                    editing = Session(start: now.addingTimeInterval(-3600), end: now, tag: tracker.selectedTag)
                } label: { Label("Add session", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            if list.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "No sessions yet" : "No sessions match “\(query)”").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(days(list)) { day in
                        Section {
                            ForEach(day.sessions) { s in
                                row(s)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { editing = s }
                                    .contextMenu {
                                        Button("Edit…") { editing = s }
                                        Button("Duplicate as new") {
                                            var c = Session(start: s.start, end: s.end ?? Date(), tag: s.tag)
                                            c.start = Date().addingTimeInterval(-(s.duration()))
                                            c.end = Date()
                                            editing = c
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) { tracker.delete(s.id) }
                                    }
                            }
                        } header: {
                            HStack {
                                Text(dayTitle(day.id)).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(Stats.format(day.total)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $editing) { s in
            EditSession(session: s,
                        isNew: !tracker.sessions.contains { $0.id == s.id },
                        tags: tracker.recentTags,
                        onSave: { tracker.upsert($0); editing = nil },
                        onDelete: { tracker.delete(s.id); editing = nil },
                        onCancel: { editing = nil })
        }
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Stats.calendar
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
    }

    private func row(_ s: Session) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Brand.color(for: s.tag)).frame(width: 4, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.tag.isEmpty ? "No tag" : s.tag)
                    .foregroundStyle(s.tag.isEmpty ? .secondary : .primary)
                Text("\(s.start.formatted(date: .omitted, time: .shortened)) – \(s.end?.formatted(date: .omitted, time: .shortened) ?? "now")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if s.end == nil {
                Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.gradient))
            }
            if s.auto {
                Text("auto-paused").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            Spacer()
            Text(Stats.format(s.duration())).font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
            Button { editing = s } label: { Image(systemName: "pencil").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
                .help("Edit")
        }
        .padding(.vertical, 3)
    }
}

private struct EditSession: View {
    @ViewState var session: Session
    let isNew: Bool
    let tags: [String]
    let onSave: (Session) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private var endBinding: Binding<Date> {
        Binding(get: { session.end ?? Date() }, set: { session.end = $0 })
    }

    private var valid: Bool { session.end.map { $0 > session.start } ?? (session.start < Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                BrandMark(size: 22)
                Text(isNew ? "Add session" : "Edit session").font(.headline)
            }
            Form {
                DatePicker("Start", selection: $session.start)
                if session.end != nil {
                    DatePicker("End", selection: endBinding)
                } else {
                    LabeledContent("End", value: "Still running")
                }
                HStack {
                    TextField("Tag", text: $session.tag, prompt: Text("No tag"))
                    if !tags.isEmpty {
                        Menu {
                            ForEach(tags, id: \.self) { t in Button(t) { session.tag = t } }
                        } label: { Image(systemName: "tag") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                LabeledContent("Duration") {
                    Text(valid ? Stats.format(session.duration()) : "End must be after start")
                        .foregroundStyle(valid ? Color.secondary : Color.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew { Button("Delete", role: .destructive, action: onDelete) }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(session) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
