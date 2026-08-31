import SwiftUI
import AppKit

// MARK: - Stick "Clear" liquid glass — single layer only

enum UI {
    static let width: CGFloat = 320
    static let radiusOuter: CGFloat = 22
    static let sectionHPadding: CGFloat = 16
    static let sectionTopPadding: CGFloat = 8
    static let sectionBottomPadding: CGFloat = 4
    static let headerSpacing: CGFloat = 6
    static let lastRowBottomInset: CGFloat = 8

    /// Horizontal inset of option-row hovers from the panel edge.
    static let rowHoverHorizontalInset: CGFloat = sectionHPadding - 10

    /// Bottom-corner radius for the last row hover, concentric with the panel curve.
    static var panelBottomHoverRadius: CGFloat {
        max(7, radiusOuter - lastRowBottomInset)
    }

    static let label = Color.primary.opacity(0.55)
    static let subtle = Color.primary.opacity(0.42)
    static let divider = Color.primary.opacity(0.06)
}

/// One glass surface. No extra stroke, clip, or shadow — those caused a double-rim with MenuBarExtra.
struct ClearGlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = UI.radiusOuter
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: UI.width)
            .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
            .background(MenuWindowConfigurator())
    }
}

/// Makes the MenuBarExtra popover window fully transparent so only our glassEffect shows.
struct MenuWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> MenuWindowConfiguratorView {
        MenuWindowConfiguratorView()
    }

    func updateNSView(_ nsView: MenuWindowConfiguratorView, context: Context) {}
}

final class MenuWindowConfiguratorView: NSView {
    private var didConfigureWindow = false
    private var didStripWrapper = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfNeeded()
    }

    override func layout() {
        super.layout()
        stripOuterWrapperIfNeeded()
        forceActiveVisualEffects(in: window?.contentView)
    }

    private func configureWindowIfNeeded() {
        guard let window, !didConfigureWindow else { return }
        didConfigureWindow = true

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false

        installActiveGlassFix(on: window)

        if let content = window.contentView {
            clearViewBackground(content)
        }
    }

    private func stripOuterWrapperIfNeeded() {
        guard !didStripWrapper, let content = window?.contentView else { return }
        guard content.bounds.width > 1, content.bounds.height > 1 else { return }

        for sub in content.subviews where sub is NSVisualEffectView {
            let fillsWindow = sub.frame.width >= content.bounds.width - 1
                && sub.frame.height >= content.bounds.height - 1
            if fillsWindow {
                sub.isHidden = true
                sub.alphaValue = 0
            }
        }
        didStripWrapper = true
        forceActiveVisualEffects(in: content)
    }

    private func clearViewBackground(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.borderWidth = 0
    }
}

func forceActiveVisualEffects(in view: NSView?) {
    guard let view else { return }
    if let ve = view as? NSVisualEffectView, !ve.isHidden {
        ve.state = .active
    }
    for sub in view.subviews {
        forceActiveVisualEffects(in: sub)
    }
}

private var installedGlassFixWindows = WeakWindowSet()

func installActiveGlassFix(on window: NSWindow) {
    guard installedGlassFixWindows.insert(window) else { return }

    let nc = NotificationCenter.default
    let apply: (Notification) -> Void = { _ in
        guard let content = window.contentView else { return }
        DispatchQueue.main.async { forceActiveVisualEffects(in: content) }
    }
    for name in [
        NSWindow.didResignKeyNotification,
        NSWindow.didResignMainNotification,
        NSWindow.didBecomeKeyNotification,
        NSWindow.didBecomeMainNotification,
    ] {
        nc.addObserver(forName: name, object: window, queue: .main, using: apply)
    }
}

/// Tracks windows we've already installed glass-fix observers on.
private final class WeakWindowSet {
    private var windows: [WeakWindow] = []

    func insert(_ window: NSWindow) -> Bool {
        windows.removeAll { $0.value == nil }
        guard !windows.contains(where: { $0.value === window }) else { return false }
        windows.append(WeakWindow(window))
        return true
    }
}

private struct WeakWindow {
    weak var value: NSWindow?
    init(_ window: NSWindow) { value = window }
}
