import AppKit
import SwiftUI

/// Tracky's visual identity: a progress ring with a glowing "playhead", warm amber→coral→pink.
/// Everything is drawn in code, so the brand costs zero bytes of image assets.
enum Brand {
    static let amber = Color(red: 1.00, green: 0.71, blue: 0.28)   // #FFB547
    static let accent = Color(red: 1.00, green: 0.42, blue: 0.29)  // #FF6B4A
    static let pink = Color(red: 1.00, green: 0.24, blue: 0.43)    // #FF3D6E
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.10)

    static var gradient: LinearGradient {
        LinearGradient(colors: [amber, accent, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let palette: [Color] = [
        accent,
        Color(red: 0.39, green: 0.40, blue: 0.95), // indigo
        Color(red: 0.08, green: 0.72, blue: 0.65), // teal
        Color(red: 0.93, green: 0.28, blue: 0.60), // pink
        Color(red: 0.96, green: 0.62, blue: 0.04), // amber
        Color(red: 0.05, green: 0.65, blue: 0.91), // sky
        Color(red: 0.13, green: 0.77, blue: 0.37), // green
        Color(red: 0.55, green: 0.36, blue: 0.96), // violet
    ]

    /// Palette slot per tag, assigned in order of first use so early tags never share a colour.
    nonisolated(unsafe) private static var slots: [String: Int] = [:]

    static func assignColors(_ sessions: [Session]) {
        var map: [String: Int] = [:]
        for s in sessions where !s.tag.isEmpty && map[s.tag] == nil { map[s.tag] = map.count }
        slots = map
    }

    /// Stable colour per tag name, so a tag looks the same everywhere.
    static func color(for tag: String) -> Color {
        if tag.isEmpty || tag == "Untagged" { return Color.gray.opacity(0.55) }
        if let i = slots[tag] { return palette[i % palette.count] }
        var h: UInt32 = 5381
        for b in tag.utf8 { h = (h &<< 5) &+ h &+ UInt32(b) }
        return palette[Int(h % UInt32(palette.count))]
    }

    enum BarState { case idle, running, paused }

    /// 18pt template glyph for the menu bar. Running: the ring fills with the current hour of the
    /// session and gains a centre dot. Paused: pause bars inside a faint ring.
    static func barIcon(_ state: BarState, progress: Double = 0.75) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let c = NSPoint(x: 9, y: 9), r: CGFloat = 6.4, lw: CGFloat = 2.1
            let track = NSBezierPath()
            track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
            track.lineWidth = lw
            NSColor.black.withAlphaComponent(0.28).setStroke()
            track.stroke()
            NSColor.black.setFill()
            NSColor.black.setStroke()

            if state == .paused {
                NSBezierPath(roundedRect: NSRect(x: 6.7, y: 6.0, width: 1.8, height: 6), xRadius: 0.9, yRadius: 0.9).fill()
                NSBezierPath(roundedRect: NSRect(x: 9.5, y: 6.0, width: 1.8, height: 6), xRadius: 0.9, yRadius: 0.9).fill()
                return true
            }
            let p = state == .running ? min(max(progress, 0.04), 0.999) : 0.75
            let end = 90 - 360 * p
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: end, clockwise: true)
            arc.lineWidth = lw
            arc.lineCapStyle = .round
            arc.stroke()
            let a = end * .pi / 180
            let head = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            NSBezierPath(ovalIn: NSRect(x: head.x - 2.2, y: head.y - 2.2, width: 4.4, height: 4.4)).fill()
            if state == .running {
                NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 4, height: 4)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// The app-icon mark in SwiftUI (dark squircle, gradient ring, white playhead).
struct BrandMark: View {
    var size: CGFloat = 20
    var progress: Double = 0.75

    var body: some View {
        let ringRadius = size * 0.303
        let lw = size * 0.08
        let angle = Angle.degrees(-90 + 360 * progress)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: lw)
                .frame(width: ringRadius * 2, height: ringRadius * 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [Brand.amber, Brand.accent, Brand.pink],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * progress)),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ringRadius * 2, height: ringRadius * 2)
            Circle()
                .fill(.white)
                .frame(width: size * 0.12, height: size * 0.12)
                .shadow(color: Brand.pink.opacity(0.8), radius: size * 0.04)
                .offset(x: ringRadius * cos(angle.radians), y: ringRadius * sin(angle.radians))
        }
        .frame(width: size, height: size)
    }
}

/// Floating "Deleted … · Undo" pill shared by the popover and stats window.
struct UndoToast: View {
    @ObservedObject var tracker: Tracker

    var body: some View {
        if let msg = tracker.undoMessage {
            HStack(spacing: 10) {
                Image(systemName: tracker.canUndo ? "trash" : "info.circle").foregroundStyle(.secondary)
                Text(msg).lineLimit(1)
                if tracker.canUndo {
                    Button("Undo") { tracker.undo() }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                        .foregroundStyle(Brand.accent)
                }
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: msg) {
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                tracker.clearUndo()
            }
        }
    }
}
