import SwiftUI

// MARK: - Control Center–style primitives (macOS Sound panel)

enum CCFont {
    static let section = Font.system(size: 11.5, weight: .semibold)
    static let trailing = Font.system(size: 11, weight: .regular)
    static let row = Font.system(size: 12, weight: .regular)
    static let caption = Font.system(size: 10.5, weight: .regular)
    static let icon = Font.system(size: 12, weight: .light)
    static let iconMedium = Font.system(size: 12, weight: .regular)
    static let checkmark = Font.system(size: 10.5, weight: .semibold)
}

struct CCHoverBackground: View {
    var cornerRadii: RectangleCornerRadii = .init(topLeading: 7, bottomLeading: 7, bottomTrailing: 7, topTrailing: 7)
    var isHovered: Bool

    var body: some View {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
            .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            .overlay {
                if isHovered {
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                }
            }
    }
}

struct CCHoverRow<Content: View>: View {
    var cornerRadii: RectangleCornerRadii = .init(topLeading: 7, bottomLeading: 7, bottomTrailing: 7, topTrailing: 7)
    var extendHorizontally: CGFloat = 10
    var extendBottom: CGFloat = 0
    var verticalPadding: CGFloat = 3
    @ViewBuilder var content: () -> Content

    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, verticalPadding)
            .background {
                CCHoverBackground(cornerRadii: cornerRadii, isHovered: hovering)
            }
            .padding(.horizontal, -extendHorizontally)
            .padding(.bottom, extendBottom > 0 ? -extendBottom : 0)
            .onHover { isHover in
                withAnimation(.easeOut(duration: 0.12)) {
                    hovering = isHover
                }
            }
    }
}

struct CCSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(CCFont.section)
                .foregroundStyle(.primary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(CCFont.trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CCDivider: View {
    var body: some View {
        Rectangle()
            .fill(UI.divider)
            .frame(height: 0.5)
            .padding(.horizontal, UI.sectionHPadding)
    }
}

struct CCOptionRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    var enabled: Bool = true
    var verticalPadding: CGFloat = 3
    var cornerRadii: RectangleCornerRadii = .init(topLeading: 7, bottomLeading: 7, bottomTrailing: 7, topTrailing: 7)
    var extendBottom: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CCHoverRow(
                cornerRadii: cornerRadii,
                extendBottom: extendBottom,
                verticalPadding: verticalPadding
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(CCFont.checkmark)
                        .foregroundStyle(.primary)
                        .frame(width: 12, alignment: .center)
                        .opacity(selected ? 1 : 0)

                    Image(systemName: symbol)
                        .font(CCFont.icon)
                        .symbolRenderingMode(.monochrome)
                        .frame(width: 18, alignment: .center)
                        .foregroundStyle(.primary.opacity(enabled ? 0.8 : 0.35))

                    Text(title)
                        .font(CCFont.row)
                        .foregroundStyle(.primary.opacity(enabled ? 1 : 0.35))

                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct CCDeviceRow: View {
    let name: String
    let subtitle: String
    var battery: Int? = nil
    var connected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(connected ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: "headphones")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(connected ? .white : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(CCFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let battery {
                HStack(spacing: 4) {
                    Text("\(battery)%")
                        .font(.system(size: 11).monospacedDigit())
                    Image(systemName: batterySymbol(for: battery))
                        .font(.system(size: 14, weight: .light))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func batterySymbol(for level: Int) -> String {
        switch level {
        case 0...10: return "battery.0percent"
        case 11...35: return "battery.25percent"
        case 36...60: return "battery.50percent"
        case 61...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct CCVolumeRow: View {
    @Binding var volume: Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "headphones")
                .font(CCFont.icon)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Slider(
                value: $volume,
                in: 0...1,
                onEditingChanged: onEditingChanged
            )
            .tint(Color.accentColor)
            .controlSize(.small)

            Image(systemName: "speaker.wave.2.fill")
                .font(CCFont.icon)
                .foregroundStyle(.secondary)
                .frame(width: 14)
        }
    }
}

struct CCConnectionControl: View {
    @ObservedObject var client: SennheiserClient

    private enum DisplayState {
        case connected, connecting, connect
    }

    private var displayState: DisplayState {
        if client.isConnected { return .connected }
        if client.connectionPhase == .connecting { return .connecting }
        if client.isBluetoothLinked { return .connecting }
        return .connect
    }

    var body: some View {
        switch displayState {
        case .connected:
            Text("Connected")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        }
                }

        case .connecting:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                Text("Connecting…")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
            }

        case .connect:
            Button {
                client.connectFirstAvailable()
            } label: {
                Text("Connect")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.82))
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

struct CCLinkButton: View {
    let title: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CCHoverRow {
                Text(title)
                    .font(.system(size: 12, weight: prominent ? .medium : .regular))
                    .foregroundStyle(prominent ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CCSection<Content: View>: View {
    var spacing: CGFloat = UI.headerSpacing
    var topPadding: CGFloat = UI.sectionTopPadding
    var bottomPadding: CGFloat = UI.sectionBottomPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(.horizontal, UI.sectionHPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
