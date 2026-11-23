import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Created when opened, fully released when closed, so charts cost nothing in the background.
@MainActor
final class StatsWindow: NSObject, NSWindowDelegate {
    private let tracker: Tracker
    private let prefs: Prefs
    private var window: NSWindow?

    init(tracker: Tracker, prefs: Prefs) {
        self.tracker = tracker
        self.prefs = prefs
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: StatsView(tracker: tracker, prefs: prefs))
            host.sceneBridgingOptions = [.toolbars, .title]
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 1080, height: 780))
            w.minSize = NSSize(width: 900, height: 600)
            w.center()
            w.setFrameAutosaveName("TrackyStats2")
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentViewController = nil
            self?.window = nil
        }
    }

    /// Spreadsheet-friendly export.
    static func exportCSV(_ sessions: [Session]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "tracky-\(Date().formatted(.iso8601.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out = "start,end,minutes,tag,auto_paused\n"
        let now = Date()
        for s in sessions {
            let end = s.end.map(f.string(from:)) ?? ""
            let tag = s.tag.contains("\"") ? "\"\(s.tag.replacingOccurrences(of: "\"", with: "\"\""))\"" : s.tag
            out += "\(f.string(from: s.start)),\(end),\(String(format: "%.1f", s.duration(now: now) / 60)),\(tag),\(s.auto ? "yes" : "")\n"
        }
        try? out.write(to: url, atomically: true, encoding: .utf8)
    }
}
