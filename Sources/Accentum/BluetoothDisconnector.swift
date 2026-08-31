import Foundation
import IOBluetooth

/// Reliable Bluetooth disconnect — `closeConnection()` alone often no-ops on recent macOS.
final class BluetoothDisconnector: NSObject {
    private var notifications: [IOBluetoothUserNotification] = []
    private var completion: (() -> Void)?
    private var pendingDevices: Set<String> = []
    private var retryWork: DispatchWorkItem?

    func disconnectAll(_ devices: [IOBluetoothDevice], completion: @escaping () -> Void) {
        cancel()
        let connected = devices.filter { $0.isConnected() }
        guard !connected.isEmpty else {
            completion()
            return
        }

        self.completion = completion
        pendingDevices = Set(connected.compactMap { $0.addressString })

        for dev in connected {
            if let note = dev.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
                notifications.append(note)
            }
            _ = dev.closeConnection()
        }

        let work = DispatchWorkItem { [weak self] in
            self?.retryIfNeeded(connected, attempt: 1)
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func retryIfNeeded(_ devices: [IOBluetoothDevice], attempt: Int) {
        let stillConnected = devices.filter { $0.isConnected() }
        guard !stillConnected.isEmpty else {
            finish()
            return
        }
        guard attempt <= 5 else {
            finish()
            return
        }

        for dev in stillConnected {
            _ = dev.closeConnection()
        }

        let work = DispatchWorkItem { [weak self] in
            self?.retryIfNeeded(devices, attempt: attempt + 1)
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let address = device.addressString {
            pendingDevices.remove(address)
        }
        if pendingDevices.isEmpty {
            finish()
        }
    }

    private func finish() {
        cancel()
        completion?()
        completion = nil
    }

    private func cancel() {
        retryWork?.cancel()
        retryWork = nil
        for note in notifications {
            note.unregister()
        }
        notifications.removeAll()
        pendingDevices.removeAll()
    }
}
