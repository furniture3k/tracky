import AppKit
import SwiftUI

/// Tracky's identity: a plain kitchen-timer dial. Flat colours, no gradients, no glow.
/// One signal colour (vermilion) is used sparingly; everything else is ink, paper and hairlines.
enum Brand {
    /// Vermilion, slightly lifted in dark mode so it holds contrast.
    static let signal = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.38, blue: 0.25, alpha: 1)
            : NSColor(srgbRed: 0.86, green: 0.27, blue: 0.15, alpha: 1)
    })
    static let paper = Color(red: 0.953, green: 0.937, blue: 0.902) // #F3EFE6
    static let hairline = Color.primary.opacity(0.10)
    static let muted = Color.primary.opacity(0.16)

    /// Muted, distinguishable tag colours (no neon).
    static let palette: [Color] = [
        Color(red: 0.86, green: 0.27, blue: 0.15), // vermilion
        Color(red: 0.18, green: 0.36, blue: 0.66), // cobalt
        Color(red: 0.35, green: 0.49, blue: 0.18), // moss
        Color(red: 0.79, green: 0.54, blue: 0.11), // ochre
        Color(red: 0.49, green: 0.29, blue: 0.53), // plum
        Color(red: 0.14, green: 0.50, blue: 0.48), // teal
        Color(red: 0.72, green: 0.31, blue: 0.42), // rose
        Color(red: 0.35, green: 0.40, blue: 0.44), // slate
    ]

    /// Palette slot per tag, in the order tags were created, so the first 8 tags never share a colour.
    nonisolated(unsafe) private static var slots: [String: Int] = [:]

    static func assignColors(tags: [String], sessions: [Session]) {
        var map: [String: Int] = [:]
        for t in tags where map[t] == nil { map[t] = map.count }
        for s in sessions where !s.tag.isEmpty && map[s.tag] == nil { map[s.tag] = map.count }
        slots = map
    }

    static func color(for tag: String) -> Color {
        if tag.isEmpty || tag == "Untagged" { return Color.gray.opacity(0.6) }
        if let i = slots[tag] { return palette[i % palette.count] }
        var h: UInt32 = 5381
        for b in tag.utf8 { h = (h &<< 5) &+ h &+ UInt32(b) }
        return palette[Int(h % UInt32(palette.count))]
    }

    enum BarState { case idle, running, paused }

    /// 18pt template glyph: a timer dial. Running fills a wedge with the current hour of the session;
    /// idle shows a single hand at 12; paused shows two bars.
    static func barIcon(_ state: BarState, progress: Double = 0) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let c = NSPoint(x: 9, y: 9), r: CGFloat = 7
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ring.lineWidth = 1.5
            ring.stroke()
            switch state {
            case .idle:
                let hand = NSBezierPath()
                hand.move(to: c)
                hand.line(to: NSPoint(x: c.x, y: c.y + r - 2.6))
                hand.lineWidth = 1.6
                hand.lineCapStyle = .round
                hand.stroke()
                NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
            case .running:
                let p = min(max(progress, 0.06), 1)
                let wedge = NSBezierPath()
                wedge.move(to: c)
                wedge.appendArc(withCenter: c, radius: r - 2.4, startAngle: 90, endAngle: 90 - 360 * p, clockwise: true)
                wedge.close()
                wedge.fill()
            case .paused:
                NSBezierPath(roundedRect: NSRect(x: 6.4, y: 5.8, width: 1.8, height: 6.4), xRadius: 0.5, yRadius: 0.5).fill()
                NSBezierPath(roundedRect: NSRect(x: 9.8, y: 5.8, width: 1.8, height: 6.4), xRadius: 0.5, yRadius: 0.5).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// The app icon in SwiftUI: paper tile, ink dial, vermilion wedge.
struct BrandMark: View {
    var size: CGFloat = 20
    var progress: Double = 0.75

    var body: some View {
        let dial = size * 0.56
        let ink = Color(white: 0.1)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Brand.paper)
                .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: max(0.5, size * 0.01)))
            Group {
                // Stopwatch crown.
                RoundedRectangle(cornerRadius: size * 0.015)
                    .fill(ink)
                    .frame(width: size * 0.12, height: size * 0.055)
                    .offset(y: -(dial / 2 + size * 0.075))
                Wedge(progress: progress)
                    .fill(Color(red: 0.86, green: 0.27, blue: 0.15))
                    .frame(width: dial * 0.79, height: dial * 0.79)
                Circle()
                    .strokeBorder(ink, lineWidth: max(1, size * 0.05))
                    .frame(width: dial, height: dial)
                Circle().fill(ink).frame(width: size * 0.085, height: size * 0.085)
            }
            .offset(y: size * 0.025)
        }
        .frame(width: size, height: size)
    }
}

/// Pie wedge from 12 o'clock clockwise.
struct Wedge: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: min(rect.width, rect.height) / 2,
                 startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Floating "Deleted … · Undo" pill shared by the popover and stats window.
struct UndoToast: View {
    @ObservedObject var tracker: Tracker

    var body: some View {
        ZStack {
            if let msg = tracker.undoMessage {
                HStack(spacing: 12) {
                    Text(msg).lineLimit(1)
                    if tracker.canUndo {
                        Button("Undo") { tracker.undo() }
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                            .foregroundStyle(Brand.signal)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.hairline))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: tracker.undoID) {
                    do { try await Task.sleep(for: .seconds(6)) } catch { return }
                    tracker.clearUndo()
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: tracker.undoID)
    }
}
