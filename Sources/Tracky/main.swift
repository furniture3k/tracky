import AppKit

/// Posted by a second launch so the running copy opens its panel instead.
let showPanelNotification = Notification.Name("app.tracky.Tracky.showPanel")

// Single instance: if Tracky is already running (from this or any other copy of the app),
// ask it to show its panel and quit before touching any data.
if let id = Bundle.main.bundleIdentifier {
    let me = NSRunningApplication.current
    let older = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter {
        $0.processIdentifier != me.processIdentifier
            && ($0.launchDate ?? .distantPast) <= (me.launchDate ?? .distantFuture)
    }
    if !older.isEmpty {
        DistributedNotificationCenter.default().postNotificationName(
            showPanelNotification, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
