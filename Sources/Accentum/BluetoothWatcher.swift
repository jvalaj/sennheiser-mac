import Foundation
import IOBluetooth

/// Fires when a paired Sennheiser headphone connects or disconnects over Bluetooth.
final class BluetoothWatcher: NSObject {
    var onHeadphonesConnected: ((IOBluetoothDevice) -> Void)?
    var onHeadphonesDisconnected: ((IOBluetoothDevice) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?

    private static let disconnectedName = NSNotification.Name("IOBluetoothDeviceDisconnectedNotification")

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDisconnectedNotification(_:)),
            name: Self.disconnectedName,
            object: nil
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard Self.isSennheiser(device) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onHeadphonesConnected?(device)
        }
    }

    @objc private func deviceDisconnectedNotification(_ notification: Notification) {
        guard let device = notification.object as? IOBluetoothDevice,
              Self.isSennheiser(device) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onHeadphonesDisconnected?(device)
        }
    }

    private static func isSennheiser(_ device: IOBluetoothDevice) -> Bool {
        let n = (device.name ?? "").uppercased()
        return ["ACCENTUM", "MOMENTUM", "SENNHEISER"].contains { n.contains($0) }
    }
}
