import Foundation
import IOBluetooth

/// Wires Bluetooth events → GAIA client, and enables login-item autostart.
final class AppCoordinator: ObservableObject {
    let client = SennheiserClient()
    private let watcher = BluetoothWatcher()

    init() {
        client.onChange = { [weak self] in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }

        LaunchAtLogin.applySavedPreference()
        watcher.onHeadphonesConnected = { [weak self] _ in
            // Let the audio profile settle before opening the GAIA control channel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.client.connectFirstAvailable()
            }
        }
        watcher.onHeadphonesDisconnected = { [weak self] _ in
            self?.client.disconnect()
        }
        watcher.start()

        // If headphones are already connected when the app starts, hook up immediately.
        if SennheiserClient.connectedAccentum() != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.client.connectFirstAvailable()
            }
        }
    }
}
