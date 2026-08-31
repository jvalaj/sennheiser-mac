import SwiftUI
import AppKit

struct MenuContentView: View {
    @EnvironmentObject var client: SennheiserClient
    @State private var localMode: NoiseControlState.Mode = .off
    @State private var localBands: [Float] = [0, 0, 0, 0, 0]
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        ZStack {
            FrostedBackground()
            RoundedRectangle(cornerRadius: UI.radiusOuter, style: .continuous)
                .fill(Color.white.opacity(0.18))

            VStack(alignment: .leading, spacing: 10) {
                headerCard
                noiseCard
                eqCard
                footerCard
            }
            .padding(10)
        }
        .frame(width: UI.width)
        .clipShape(RoundedRectangle(cornerRadius: UI.radiusOuter, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: UI.radiusOuter, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.65), .white.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
        .background(ClearWindowBackground())
        .preferredColorScheme(.light)
        .onAppear {
            syncLocalMode()
            localBands = client.eqBands
        }
        .onChange(of: client.noise.active) { mode in
            if mode != .unknown { localMode = mode }
        }
        .onChange(of: client.eqBands) { bands in
            localBands = bands
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        FrostedCard(padding: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(client.deviceName.isEmpty ? "Accentum" : client.deviceName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    Text(statusLine)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(UI.label)
                        .lineLimit(2)
                }
                Spacer(minLength: 10)
                if client.isConnected, let battery = client.battery {
                    Text("\(battery)%")
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(UI.subtle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.28))
                        }
                }
            }
        }
    }

    private var noiseCard: some View {
        FrostedCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Noise Control")

                Picker("Mode", selection: $localMode) {
                    Text("Cancel").tag(NoiseControlState.Mode.anc)
                    Text("Transparency").tag(NoiseControlState.Mode.transparency)
                    Text("Off").tag(NoiseControlState.Mode.off)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!client.isConnected)
                .onChange(of: localMode) { mode in
                    client.setNoiseMode(mode)
                }
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: UI.radiusPill + 2, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                }
            }
        }
    }

    private var eqCard: some View {
        FrostedCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("Equalizer")
                    .padding(.bottom, 12)

                row("Preset") {
                    Picker("", selection: presetBinding) {
                        ForEach(EqPreset.all, id: \.name) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                        if client.eqPreset == "Custom" {
                            Text("Custom").tag("Custom")
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 130)
                }

                hairline.padding(.vertical, 10)

                toggleRow("Bass Boost", isOn: Binding(
                    get: { client.bassBoost },
                    set: { client.setBassBoost($0) }
                ))

                if client.eqPreset == "Custom" {
                    hairline.padding(.vertical, 10)
                    customBands
                }
            }
        }
        .disabled(!client.isConnected)
    }

    private var footerCard: some View {
        FrostedCard(padding: 12) {
            VStack(spacing: 10) {
                Toggle(isOn: $launchAtLogin) {
                    Text("Open at Login")
                        .font(.system(size: 12, design: .rounded))
                }
                .toggleStyle(.switch)
                .tint(.primary.opacity(0.7))
                .onChange(of: launchAtLogin) { on in
                    LaunchAtLogin.isEnabled = on
                }

                HStack {
                    Button {
                        client.connectFirstAvailable()
                    } label: {
                        Text(client.isConnected ? "Connected" : "Connect")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(client.isConnected ? UI.subtle : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(client.isConnected ? 0.15 : 0.35))
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(client.connectionPhase == .connecting)

                    Spacer()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(UI.label)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.2))
                    }
                }
            }
        }
    }

    // MARK: - Custom EQ

    private var customBands: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { i in
                HStack(spacing: 10) {
                    Text(EqPreset.bands[i])
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(UI.label)
                        .frame(width: 34, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(localBands[i]) },
                            set: { localBands[i] = Float($0) }
                        ),
                        in: Double(-EqPreset.gainLimit)...Double(EqPreset.gainLimit),
                        step: 0.5,
                        onEditingChanged: { editing in
                            if !editing {
                                client.setEqBand(i, localBands[i])
                            }
                        }
                    )
                    .tint(.primary.opacity(0.55))
                }
            }
        }
    }

    // MARK: - Bindings

    private var statusLine: String {
        switch client.connectionPhase {
        case .connected:
            return client.noise.active == .unknown ? "Connected" : client.noise.active.rawValue
        case .connecting:
            return "Connecting…"
        case .failed:
            return client.lastError.isEmpty ? "Connection failed" : client.lastError
        case .idle:
            return "Not connected"
        }
    }

    private var statusColor: Color {
        switch client.connectionPhase {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .idle: return UI.label
        }
    }

    private func syncLocalMode() {
        let mode = client.noise.active
        if mode != .unknown { localMode = mode }
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { client.eqPreset },
            set: { name in
                if let preset = EqPreset.all.first(where: { $0.name == name }) {
                    client.applyEqPreset(name: name, gains: preset.gains)
                }
            }
        )
    }

    // MARK: - Primitives

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .kerning(0.6)
            .foregroundStyle(UI.label)
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, design: .rounded))
            Spacer()
            trailing()
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 13, design: .rounded))
        }
        .toggleStyle(.switch)
        .tint(.primary.opacity(0.7))
    }

    private var hairline: some View {
        Rectangle()
            .fill(UI.hairline)
            .frame(height: 0.5)
    }
}
