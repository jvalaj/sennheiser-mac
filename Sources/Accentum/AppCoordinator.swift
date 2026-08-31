import Foundation
import IOBluetooth

/// Wires Bluetooth events → GAIA client, and enables login-item autostart.
final class AppCoordinator: ObservableObject {
    let client = SennheiserClient()
    private let watcher = BluetoothWatcher()
    private let wiredMonitor = WiredAudioMonitor()

    private static let bootstrapAttempts = 10
    private static let bootstrapInterval: TimeInterval = 0.3

    init() {
        client.onChange = { [weak self] in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }

        LaunchAtLogin.applySavedPreference()

        wiredMonitor.onChange = { [weak self] in
            guard let self else { return }
            self.client.syncWiredAudio(deviceName: self.wiredMonitor.deviceName)
        }
        wiredMonitor.start()
        client.syncWiredAudio(deviceName: wiredMonitor.deviceName)

        watcher.onHeadphonesConnected = { [weak self] _ in
            guard let self, self.client.shouldAcceptBluetoothAutoConnect() else { return }
            // Let the audio profile settle before opening the GAIA control channel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.wiredMonitor.refresh()
                self.client.syncWiredAudio(deviceName: self.wiredMonitor.deviceName)
                guard self.client.shouldAcceptBluetoothAutoConnect() else { return }
                self.client.autoConnectBluetoothIfNeeded()
            }
        }
        watcher.onHeadphonesDisconnected = { [weak self] _ in
            guard let self else { return }
            self.wiredMonitor.refresh()
            self.client.syncWiredAudio(deviceName: self.wiredMonitor.deviceName)
            self.client.disconnect()
        }
        watcher.start()

        bootstrapConnection(attempt: 0)
    }

    /// Poll for USB-C audio before attempting any automatic Bluetooth GAIA connection.
    private func bootstrapConnection(attempt: Int) {
        wiredMonitor.refresh()
        client.syncWiredAudio(deviceName: wiredMonitor.deviceName)

        if client.isWiredUSBActive {
            client.refreshOnMenuOpen()
            return
        }

        if attempt < Self.bootstrapAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.bootstrapInterval) { [weak self] in
                self?.bootstrapConnection(attempt: attempt + 1)
            }
            return
        }

        client.autoConnectBluetoothIfNeeded()
    }
}
