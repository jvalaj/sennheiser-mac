import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var client: SennheiserClient
    @StateObject private var media = MediaControls()
    @State private var localMode: NoiseControlState.Mode = .off

    var body: some View {
        ClearGlassPanel {
            VStack(alignment: .leading, spacing: 0) {
                soundSection
                CCDivider()
                deviceSection
                CCDivider()
                noiseSection
                bugReportRow
            }
        }
        .onAppear {
            syncLocalMode()
            media.refreshVolume()
            client.refreshOnMenuOpen()
        }
        .onChange(of: client.isWiredUSBActive) { _, _ in
            client.refreshOnMenuOpen()
        }
        .onChange(of: client.noise.active) { _, mode in
            if mode != .unknown { localMode = mode }
        }
    }

    // MARK: - Sound

    private var soundSection: some View {
        CCSection(spacing: 8, topPadding: 10, bottomPadding: 6) {
            HStack(alignment: .center) {
                Text("Sound")
                    .font(CCFont.section)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                CCConnectionControl(client: client)
            }

            CCVolumeRow(
                volume: Binding(
                    get: { media.volume },
                    set: { media.setVolume($0) }
                ),
                onEditingChanged: { editing in
                    if editing {
                        media.beginVolumeDrag()
                    } else {
                        media.endVolumeDrag()
                    }
                }
            )
        }
    }

    // MARK: - Device

    private var deviceSection: some View {
        CCSection(topPadding: 6, bottomPadding: 2) {
            CCSectionHeader(title: "Headphones")
            CCDeviceRow(
                name: client.deviceName.isEmpty ? "Accentum" : client.deviceName,
                subtitle: statusLine,
                battery: client.isConnected ? client.battery : nil,
                connection: deviceConnectionStyle
            )
        }
    }

    // MARK: - Noise Control

    private var noiseSection: some View {
        CCSection(spacing: 6, topPadding: 6, bottomPadding: 4) {
            CCSectionHeader(
                title: "Noise Control",
                trailing: client.isConnectingBluetooth ? "Connecting…" : nil
            )
            ZStack(alignment: .topLeading) {
                if client.showsWiredBluetoothPrompt {
                    CCWiredBluetoothPrompt(client: client)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else {
                    VStack(spacing: 0) {
                        noiseRow(.transparency, title: "Transparency", symbol: "ear", isLast: false)
                        noiseRow(.anc, title: "Noise Cancellation", symbol: "wave.3.right", isLast: false)
                        noiseRow(.off, title: "Off", symbol: "speaker", isLast: true)
                    }
                    .opacity(client.isConnected ? 1 : 0.5)
                    .allowsHitTesting(client.isConnected)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: client.showsWiredBluetoothPrompt)
        }
    }

    private func noiseRow(_ mode: NoiseControlState.Mode, title: String, symbol: String, isLast: Bool) -> some View {
        CCOptionRow(
            title: title,
            symbol: symbol,
            selected: localMode == mode,
            enabled: client.isConnected,
            verticalPadding: 6,
            cornerRadii: isLast
                ? .init(
                    topLeading: 7,
                    bottomLeading: UI.panelBottomHoverRadius,
                    bottomTrailing: UI.panelBottomHoverRadius,
                    topTrailing: 7
                )
                : .init(topLeading: 7, bottomLeading: 7, bottomTrailing: 7, topTrailing: 7),
            extendBottom: 0
        ) {
            guard localMode != mode else { return }
            localMode = mode
            client.setNoiseMode(mode)
        }
    }

    private var bugReportRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Report a bug") {
                NSWorkspace.shared.open(Support.bugReportURL(
                    deviceName: client.deviceName,
                    firmware: client.firmware,
                    model: client.profile.displayName,
                    connected: client.isConnected
                ))
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .opacity(0.75)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, UI.sectionHPadding)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private var deviceConnectionStyle: CCDeviceRow.DeviceConnectionStyle {
        if client.isConnected || client.isConnectingBluetooth { return .bluetooth }
        if client.isWiredUSBActive { return .wired }
        return .disconnected
    }

    private var statusLine: String {
        switch client.connectionPhase {
        case .connected:
            return client.noise.active == .unknown ? "Bluetooth · controls available" : client.noise.active.rawValue
        case .wired:
            return "USB-C · audio only"
        case .disconnecting:
            return "Disconnecting…"
        case .connecting:
            return "Connecting Bluetooth…"
        case .failed:
            return client.lastError.isEmpty ? "Connection failed" : client.lastError
        case .idle:
            if client.isWiredUSBActive, !client.isBluetoothLinked {
                return "USB-C · audio only"
            }
            return client.isBluetoothLinked ? "Connecting…" : "Not connected"
        }
    }

    private func syncLocalMode() {
        let mode = client.noise.active
        if mode != .unknown { localMode = mode }
    }
}
