import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var client: SennheiserClient
    @StateObject private var media = MediaControls()
    @State private var localMode: NoiseControlState.Mode = .off

    var body: some View {
        ClearGlassPanel {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    soundSection
                    CCDivider()
                    deviceSection
                    CCDivider()
                    noiseSection
                }

                bugReportLink
                    .padding(.trailing, 12)
                    .padding(.bottom, 7)
            }
        }
        .onAppear {
            syncLocalMode()
            media.refreshVolume()
            client.ensureConnected()
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
                connected: client.isConnected
            )
        }
    }

    // MARK: - Noise Control

    private var noiseSection: some View {
        CCSection(spacing: 6, topPadding: 6, bottomPadding: UI.lastRowBottomInset) {
            CCSectionHeader(title: "Noise Control")
            VStack(spacing: 0) {
                noiseRow(.transparency, title: "Transparency", symbol: "ear", isLast: false)
                noiseRow(.anc, title: "Noise Cancellation", symbol: "wave.3.right", isLast: false)
                noiseRow(.off, title: "Off", symbol: "speaker", isLast: true)
            }
        }
        .opacity(client.isConnected ? 1 : 0.45)
        .allowsHitTesting(client.isConnected)
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

    private var bugReportLink: some View {
        Link("bug", destination: Support.bugReportURL(
            deviceName: client.deviceName,
            firmware: client.firmware,
            model: client.profile.displayName,
            connected: client.isConnected
        ))
        .font(.system(size: 8.5, weight: .regular))
        .foregroundStyle(.tertiary)
        .opacity(0.55)
    }

    // MARK: - Helpers

    private var statusLine: String {
        switch client.connectionPhase {
        case .connected:
            return client.noise.active == .unknown ? "Connected" : client.noise.active.rawValue
        case .connecting:
            return "Connecting…"
        case .failed:
            return client.lastError.isEmpty ? "Connection failed" : client.lastError
        case .idle:
            return client.isBluetoothLinked ? "Connecting…" : "Not connected"
        }
    }

    private func syncLocalMode() {
        let mode = client.noise.active
        if mode != .unknown { localMode = mode }
    }
}
