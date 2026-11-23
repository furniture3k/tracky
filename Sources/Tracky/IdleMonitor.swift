import AppKit
import CoreGraphics

/// Optional idle auto-pause. It never polls on its own: `check()` piggybacks on the menu bar's
/// once-a-minute tick, and sleep/lock/wake are system notifications observed only while enabled.
@MainActor
final class IdleMonitor: ObservableObject {
    static let choices = [0, 5, 10, 15, 30]

    /// Minutes of inactivity before pausing; 0 = off.
    @Published var minutes: Int {
        didSet { UserDefaults.standard.set(minutes, forKey: "idleMinutes"); updateObservers(); onChange?() }
    }
    @Published var autoResume: Bool {
        didSet { UserDefaults.standard.set(autoResume, forKey: "idleAutoResume"); onChange?() }
    }

    var enabled: Bool { minutes > 0 }
    var onChange: (() -> Void)?

    private let tracker: Tracker
    /// True while the screen is locked or asleep. Never auto-resume then: a mouse nudge on the
    /// lock screen counts as "activity" but isn't you working.
    private var locked = false
    private var asleep = false
    private var away: Bool { locked || asleep }
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(tracker: Tracker) {
        self.tracker = tracker
        let d = UserDefaults.standard
        minutes = d.object(forKey: "idleMinutes") as? Int ?? 10
        autoResume = d.object(forKey: "idleAutoResume") as? Bool ?? true
        updateObservers()
    }

    /// Seconds since the last keyboard/mouse/trackpad input.
    static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func check() {
        guard enabled else { return }
        let idle = Self.idleSeconds
        if tracker.isRunning, idle >= Double(minutes * 60) {
            tracker.autoPause(at: Date().addingTimeInterval(-idle))
        } else if tracker.isPaused, autoResume, !away, idle < 60 {
            tracker.resume(at: Date().addingTimeInterval(-idle)) // back-date to when you returned
        }
    }

    private func pauseNow() {
        if enabled, tracker.isRunning { tracker.autoPause(at: Date()) }
    }

    private func updateObservers() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        guard enabled else { return }

        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        func observe(_ c: NotificationCenter, _ name: String, _ f: @escaping @MainActor () -> Void) {
            observers.append((c, c.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { f() }
            }))
        }
        observe(ws, NSWorkspace.willSleepNotification.rawValue) { [weak self] in self?.asleep = true; self?.pauseNow() }
        observe(ws, NSWorkspace.screensDidSleepNotification.rawValue) { [weak self] in self?.asleep = true; self?.pauseNow() }
        observe(dist, "com.apple.screenIsLocked") { [weak self] in self?.locked = true; self?.pauseNow() }
        // Waking alone isn't proof you're back (the screen is often still locked): the next minute
        // tick resumes if there's real input and the screen isn't locked. Unlocking resumes at once.
        observe(ws, NSWorkspace.didWakeNotification.rawValue) { [weak self] in self?.asleep = false }
        observe(ws, NSWorkspace.screensDidWakeNotification.rawValue) { [weak self] in self?.asleep = false }
        observe(dist, "com.apple.screenIsUnlocked") { [weak self] in
            guard let self else { return }
            locked = false
            if enabled, autoResume, !asleep, tracker.isPaused { tracker.resume() }
        }
    }
}
