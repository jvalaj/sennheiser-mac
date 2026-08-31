import SwiftUI
import AppKit

struct FrostedBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = UI.radiusOuter
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ClearWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isOpaque = false
            view.window?.backgroundColor = .clear
            view.window?.hasShadow = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct FrostedCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: UI.radiusInner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: UI.radiusInner, style: .continuous)
                            .fill(Color.white.opacity(0.22))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: UI.radiusInner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    }
            }
    }
}

enum UI {
    static let width: CGFloat = 288
    static let radiusOuter: CGFloat = 22
    static let radiusInner: CGFloat = 14
    static let radiusPill: CGFloat = 10

    static let label = Color.primary.opacity(0.5)
    static let subtle = Color.primary.opacity(0.38)
    static let hairline = Color.white.opacity(0.35)
}
