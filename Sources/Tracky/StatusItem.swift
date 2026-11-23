import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let tracker = Tracker()
    let prefs = Prefs()
    lazy var idle = IdleMonitor(tracker: tracker)
    lazy var statsWindow = StatsWindow(tracker: tracker, prefs: prefs)

    private var item: NSStatusItem!
    private var popover: NSPopover?
    private var timer: Timer?
    private var timerKey: Date?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Tracky"
        if let b = item.button {
            b.target = self
            b.action = #selector(clicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.imagePosition = .imageLeading
        }
        tracker.onChange = { [weak self] in self?.refresh() }
        idle.onChange = { [weak self] in self?.refresh() }
        prefs.onChange = { [weak self] in self?.refresh() }
        hotKey = HotKey { [weak self] in MainActor.assumeIsolated { self?.tracker.toggle() } }
        // Midnight rollover for "Today's total" mode.
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLabel() }
        }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.endForQuit()
    }

    // MARK: Click handling

    @objc private func clicked() {
        // Right-click (or ctrl-click) toggles tracking instantly; left-click opens the popover.
        if let e = NSApp.currentEvent, e.type == .rightMouseUp || e.modifierFlags.contains(.control) {
            popover?.performClose(nil)
            tracker.toggle()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if let p = popover, p.isShown { p.performClose(nil); return }
        guard let button = item.button else { return }
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        let host = NSHostingController(rootView: PopoverView(
            tracker: tracker, idle: idle, prefs: prefs,
            openStats: { [weak self] in self?.popover?.performClose(nil); self?.statsWindow.show() }
        ))
        host.sizingOptions = .preferredContentSize
        p.contentViewController = host
        popover = p
        NSApp.activate()
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil // drop the SwiftUI tree; nothing stays alive while closed
    }

    // MARK: Menu bar label + minute timer

    private func refresh() {
        updateLabel()
        let needsTimer = tracker.isRunning || (tracker.isPaused && idle.enabled && idle.autoResume)
        let key = tracker.running?.start ?? (needsTimer ? .distantPast : nil)
        guard key != timerKey else { return }
        timer?.invalidate()
        timer = nil
        timerKey = key
        guard needsTimer else { return }
        // Fire on minute boundaries of the running session so "1h 23m" flips on time.
        let now = Date()
        let base = tracker.running?.start ?? now
        let elapsed = now.timeIntervalSince(base)
        let first = base.addingTimeInterval((floor(elapsed / 60) + 1) * 60)
        let t = Timer(fire: first, interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        idle.check()   // may pause/resume, which calls refresh()
        updateLabel()
    }

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)

    private func updateLabel() {
        guard let b = item?.button else { return }
        let now = Date()
        var title = ""
        let image: NSImage
        if let r = tracker.running {
            let elapsed = r.duration(now: now)
            image = Brand.barIcon(.running, progress: elapsed.truncatingRemainder(dividingBy: 3600) / 3600)
            switch prefs.barMode {
            case .session: title = Stats.format(elapsed)
            case .today: title = Stats.format(tracker.tracked(since: Stats.calendar.startOfDay(for: now), now: now))
            case .icon: break
            }
        } else if tracker.isPaused {
            image = Brand.barIcon(.paused)
            if prefs.barMode != .icon { title = "Paused" }
        } else {
            image = Brand.barIcon(.idle)
            if prefs.barMode == .today {
                let today = tracker.tracked(since: Stats.calendar.startOfDay(for: now), now: now)
                if today >= 60 { title = Stats.format(today) }
            }
        }
        b.image = image
        b.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " " + title, attributes: [.font: Self.font])
        b.appearsDisabled = tracker.isPaused
        b.toolTip = tracker.isRunning ? "Tracky is tracking — right-click or ⌥⌘T to stop"
                                      : "Tracky — right-click or ⌥⌘T to start"
    }
}
