import SwiftUI

/// Liquid Glass on macOS 26+, sensible equivalents on macOS 14–15.
extension View {
    @ViewBuilder func softScrollEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }

    /// Tinted Liquid Glass button on macOS 26+, bordered-prominent before.
    @ViewBuilder func prominentButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
    }

    /// Clear Liquid Glass button on macOS 26+, bordered before.
    @ViewBuilder func glassButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass) } else { buttonStyle(.bordered).buttonBorderShape(.capsule) }
    }

    /// Interactive glass capsule (optionally tinted) for custom controls like tag chips.
    @ViewBuilder func glassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(), in: Capsule())
        } else {
            background(Capsule().fill(tint ?? Color.primary.opacity(0.07)))
        }
    }

    /// Glass panel for floating UI (toasts).
    @ViewBuilder func glassPanel(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Groups glass shapes so neighbours blend and morph (macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: spacing) { content() } } else { content() }
    }
}

/// Sets the hosting window's title and subtitle. SwiftUI's navigationTitle doesn't reach a hand-made NSWindow.
struct WindowTitle: NSViewRepresentable {
    let title: String
    let subtitle: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let (t, s) = (title, subtitle)
        DispatchQueue.main.async {
            view.window?.title = t
            view.window?.subtitle = s
        }
    }
}
