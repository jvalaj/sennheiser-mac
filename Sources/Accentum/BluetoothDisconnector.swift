import Foundation
import IOBluetooth

/// Reliable Bluetooth disconnect — `closeConnection()` alone often no-ops on recent macOS.
final class BluetoothDisconnector: NSObject {
    private var notifications: [IOBluetoothUserNotification] = []
    private var completion: (() -> Void)?
    private var pendingDevices: Set<String> = []
    private var retryWork: DispatchWorkItem?
    private var pollWork: DispatchWorkItem?

    private static let firstRetryDelay: TimeInterval = 0.12
    private static let retryInterval: TimeInterval = 0.2
    private static let maxAttempts = 4
    private static let pollInterval: TimeInterval = 0.08
    private static let maxWait: TimeInterval = 2.5

    func disconnectAll(_ devices: [IOBluetoothDevice], completion: @escaping () -> Void) {
        cancel()
        let connected = devices.filter { $0.isConnected() }
        guard !connected.isEmpty else {
            completion()
            return
        }

        self.completion = completion
        pendingDevices = Set(connected.compactMap { $0.addressString })
        let deadline = Date().addingTimeInterval(Self.maxWait)

        for dev in connected {
            if let note = dev.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
                notifications.append(note)
            }
            _ = dev.closeConnection()
        }

        schedulePoll(connected, deadline: deadline)

        let work = DispatchWorkItem { [weak self] in
            self?.retryIfNeeded(connected, attempt: 1, deadline: deadline)
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstRetryDelay, execute: work)
    }

    private func schedulePoll(_ devices: [IOBluetoothDevice], deadline: Date) {
        pollWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if devices.allSatisfy({ !$0.isConnected() }) {
                self.finish()
                return
            }
            if Date() >= deadline {
                self.finish()
                return
            }
            self.schedulePoll(devices, deadline: deadline)
        }
        pollWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval, execute: work)
    }

    private func retryIfNeeded(_ devices: [IOBluetoothDevice], attempt: Int, deadline: Date) {
        let stillConnected = devices.filter { $0.isConnected() }
        guard !stillConnected.isEmpty else {
            finish()
            return
        }
        guard attempt <= Self.maxAttempts, Date() < deadline else {
            finish()
            return
        }

        for dev in stillConnected {
            _ = dev.closeConnection()
        }

        let work = DispatchWorkItem { [weak self] in
            self?.retryIfNeeded(devices, attempt: attempt + 1, deadline: deadline)
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryInterval, execute: work)
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
        let done = completion
        cancel()
        done?()
    }

    private func cancel() {
        retryWork?.cancel()
        retryWork = nil
        pollWork?.cancel()
        pollWork = nil
        for note in notifications {
            note.unregister()
        }
        notifications.removeAll()
        pendingDevices.removeAll()
        completion = nil
    }
}
