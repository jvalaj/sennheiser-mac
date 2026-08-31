import Foundation
import IOBluetooth
import Combine

final class SennheiserClient: NSObject, ObservableObject {
    enum ConnectionPhase: Equatable {
        case idle, connecting, connected, failed
    }

    private(set) var deviceName: String = ""
    private(set) var isConnected = false
    private(set) var connectionPhase: ConnectionPhase = .idle
    private(set) var modelId: String = ""
    private(set) var firmware: String = ""
    private(set) var battery: Int?
    private(set) var codec: String = "—"
    private(set) var noise = NoiseControlState()
    private(set) var lastError: String = ""

    var profile: DeviceProfile { DeviceProfile.resolve(modelId: modelId, name: deviceName) }

    private(set) var eqBands: [Float] = [0, 0, 0, 0, 0]
    private(set) var eqPreset: String = "Flat"
    private(set) var bassBoost = false

    var onChange: (() -> Void)?

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var rxBuffer: [UInt8] = []
    private var connectionTimeout: DispatchWorkItem?
    private var retryTimer: Timer?
    private var connectGeneration = 0
    private let ioQueue = DispatchQueue(label: "accentum.gaia.io", qos: .userInitiated)
    private var modeStepWork: DispatchWorkItem?

    private static let nameHints = ["ACCENTUM", "MOMENTUM", "SENNHEISER", "CX", "HD "]
    private static let accentumGaiaChannel: BluetoothRFCOMMChannelID = 15

    static func candidateDevices() -> [IOBluetoothDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired.filter { dev in
            let n = (dev.name ?? "").uppercased()
            return nameHints.contains { n.contains($0) }
        }
    }

    static func connectedAccentum() -> IOBluetoothDevice? {
        candidateDevices().first { $0.isConnected() }
    }

    func connect(to dev: IOBluetoothDevice) {
        cancelTimers()
        connectGeneration += 1
        let generation = connectGeneration

        channel?.close()
        channel = nil
        rxBuffer.removeAll()
        isConnected = false
        connectionPhase = .connecting
        lastError = ""
        clearDeviceState()

        device = dev
        deviceName = dev.name ?? dev.addressString ?? "Sennheiser"
        notify()

        scheduleConnectionTimeout(generation: generation)
        dev.performSDPQuery(self)
    }

    func connectFirstAvailable() {
        cancelRetryTimer()
        if let connected = Self.connectedAccentum() {
            connect(to: connected)
            return
        }
        if let first = Self.candidateDevices().first {
            connect(to: first)
            return
        }
        connectionPhase = .failed
        fail("No paired Accentum found. Pair in System Settings → Bluetooth.")
        scheduleRetry()
    }

    func disconnect() {
        cancelTimers()
        connectGeneration += 1
        channel?.close()
        channel = nil
        device = nil
        isConnected = false
        connectionPhase = .idle
        rxBuffer.removeAll()
        notify()
    }

    private func clearDeviceState() {
        battery = nil
        modelId = ""
        firmware = ""
        codec = "—"
        noise = NoiseControlState()
        eqBands = [0, 0, 0, 0, 0]
        eqPreset = "Flat"
        bassBoost = false
    }

    private func cancelTimers() {
        connectionTimeout?.cancel()
        connectionTimeout = nil
        cancelRetryTimer()
    }

    private func cancelRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func scheduleConnectionTimeout(generation: Int) {
        connectionTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectGeneration == generation, !self.isConnected else { return }
            self.connectionPhase = .failed
            self.fail("Couldn't reach headphones. Close the Sennheiser app on your phone, then tap Connect.")
            self.channel?.close()
            self.channel = nil
            self.scheduleRetry()
        }
        connectionTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.retryTimer = nil
            guard let self, !self.isConnected else { return }
            self.connectFirstAvailable()
        }
    }

    private func connectionSucceeded() {
        connectionTimeout?.cancel()
        connectionTimeout = nil
        cancelRetryTimer()
        isConnected = true
        connectionPhase = .connected
        lastError = ""
    }

    private func openSerialPortChannel(on dev: IOBluetoothDevice) {
        var channelID: BluetoothRFCOMMChannelID = 0
        var found = false

        if let records = dev.services as? [IOBluetoothSDPServiceRecord] {
            for rec in records where (rec.getServiceName() ?? "").uppercased() == "GAIA" {
                if rec.getRFCOMMChannelID(&channelID) == kIOReturnSuccess { found = true; break }
            }
            if !found {
                for rec in records {
                    let name = (rec.getServiceName() ?? "").lowercased()
                    if name.contains("hands-free") || name.contains("headset") { continue }
                    if rec.getRFCOMMChannelID(&channelID) == kIOReturnSuccess { found = true; break }
                }
            }
        }
        if !found,
           let record = dev.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1101)),
           record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
            found = true
        }
        if !found, (dev.name ?? "").uppercased().contains("ACCENTUM") {
            channelID = Self.accentumGaiaChannel
            found = true
        }
        guard found else {
            connectionPhase = .failed
            fail("No GAIA service on \(deviceName). Try reconnecting in Bluetooth settings.")
            scheduleRetry()
            return
        }
        var ch: IOBluetoothRFCOMMChannel?
        let res = dev.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        if res != kIOReturnSuccess {
            connectionPhase = .failed
            fail("Bluetooth channel blocked (error \(res)). Close Sennheiser app on your phone.")
            scheduleRetry()
        } else {
            channel = ch
        }
    }

    func send(vendor: UInt16 = GAIA.vendorSennheiser, _ command: UInt16, _ payload: [UInt8] = []) {
        guard isConnected else { return }
        ioQueue.async { [weak self] in
            guard let self, let ch = self.channel else { return }
            let data = GAIA.frame(vendor: vendor, command: command, payload: payload)
            var frame = [UInt8](data)
            frame.withUnsafeMutableBytes { raw in
                _ = ch.writeSync(raw.baseAddress, length: UInt16(raw.count))
            }
        }
    }

    private func sendOnIO(vendor: UInt16 = GAIA.vendorSennheiser, _ command: UInt16, _ payload: [UInt8] = []) {
        guard let ch = channel, isConnected else { return }
        let data = GAIA.frame(vendor: vendor, command: command, payload: payload)
        var frame = [UInt8](data)
        frame.withUnsafeMutableBytes { raw in
            _ = ch.writeSync(raw.baseAddress, length: UInt16(raw.count))
        }
    }

    private func refreshAll() {
        send(SennCmd.registerNotification, [SennCmd.featureBattery])
        send(SennCmd.registerNotification, [SennCmd.featureANC])
        send(SennCmd.registerNotification, [SennCmd.featureUserEQ])
        send(SennCmd.modelIdGet)
        send(SennCmd.fwVersionGet)
        send(SennCmd.batteryGet)
        send(SennCmd.codecGet)
        send(SennCmd.ancOnGet)
        send(SennCmd.transparencyOnGet)
        send(SennCmd.transparencyGet)
        send(SennCmd.eqConfigGet)
        for b in UInt8(0)..<5 { send(SennCmd.eqBandGet, [b]) }
        send(SennCmd.bassBoostGet)
    }

    func setNoiseMode(_ mode: NoiseControlState.Mode) {
        guard mode != .unknown else { return }
        let current = noise.active
        if current == mode { return }

        let wasAnc = noise.ancOn == true
        let wasTransp = noise.transparencyOn == true
        applyOptimisticNoise(mode)
        notify()

        modeStepWork?.cancel()
        var steps: [(UInt16, [UInt8])] = []
        switch mode {
        case .anc:
            // Turn transparency off first only if it was on, then enable ANC.
            if wasTransp { steps.append((SennCmd.transparencyOnSet, [0])) }
            if !wasAnc || wasTransp { steps.append((SennCmd.ancOnSet, [1])) }
        case .transparency:
            // Single command when coming from ANC — the firmware switches the
            // audio pipeline once. Sending ANC-off + transparency-on back-to-back
            // was causing music to stop on Accentum.
            if wasTransp {
                return
            } else if wasAnc {
                steps.append((SennCmd.transparencyOnSet, [1]))
            } else {
                steps.append((SennCmd.transparencyOnSet, [1]))
            }
        case .off:
            if wasTransp { steps.append((SennCmd.transparencyOnSet, [0])) }
            if wasAnc { steps.append((SennCmd.ancOnSet, [0])) }
        case .unknown:
            return
        }
        guard !steps.isEmpty else { return }
        sendModeSteps(steps)
    }

    private func applyOptimisticNoise(_ mode: NoiseControlState.Mode) {
        switch mode {
        case .anc:
            noise.ancOn = true
            noise.transparencyOn = false
        case .transparency:
            noise.ancOn = false
            noise.transparencyOn = true
        case .off:
            noise.ancOn = false
            noise.transparencyOn = false
        case .unknown:
            break
        }
    }

    /// Space commands apart when multiple are unavoidable (e.g. turning both modes off).
    private func sendModeSteps(_ steps: [(UInt16, [UInt8])]) {
        let gap: TimeInterval = steps.count > 1 ? 0.35 : 0
        ioQueue.async { [weak self] in
            guard let self else { return }
            for (i, step) in steps.enumerated() {
                if i > 0 { Thread.sleep(forTimeInterval: gap) }
                self.sendOnIO(step.0, step.1)
            }
        }
    }

    private var transpWork: DispatchWorkItem?
    func setTransparencyLevel(_ level: UInt8) {
        noise.transparencyLevel = level
        notify()
        transpWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.send(SennCmd.transparencySet, [level])
        }
        transpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    func applyEqPreset(name: String, gains: [Float]) {
        eqPreset = name
        eqBands = gains
        notify()
        ioQueue.async { [weak self] in
            guard let self else { return }
            for (i, g) in gains.enumerated() {
                if i > 0 { Thread.sleep(forTimeInterval: 0.03) }
                let raw = Int8(clamping: Int((g * 10).rounded()))
                self.sendOnIO(SennCmd.eqBandSet, [UInt8(i), UInt8(bitPattern: raw)])
            }
        }
    }

    func setEqBand(_ index: Int, _ gain: Float) {
        guard eqBands.indices.contains(index) else { return }
        eqBands[index] = gain
        eqPreset = "Custom"
        notify()
        sendEqBand(index, gain)
    }

    func setBassBoost(_ on: Bool) {
        bassBoost = on
        notify()
        send(SennCmd.bassBoostSet, [on ? 1 : 0])
    }

    private var eqWork: [Int: DispatchWorkItem] = [:]
    private func sendEqBand(_ index: Int, _ gainDB: Float) {
        eqWork[index]?.cancel()
        let raw = Int8(clamping: Int((gainDB * 10).rounded()))
        let work = DispatchWorkItem { [weak self] in
            self?.send(SennCmd.eqBandSet, [UInt8(index), UInt8(bitPattern: raw)])
        }
        eqWork[index] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    func refresh() { refreshAll() }

    private func handle(_ pkt: GAIA.Packet) {
        let p = pkt.payload
        switch pkt.command {
        case SennCmd.ancOnResp, SennCmd.ancOnNotif:
            if let v = p.first { noise.ancOn = v != 0 }
        case SennCmd.transparencyOnResp, SennCmd.transparencyOnNotif:
            if let v = p.first { noise.transparencyOn = v != 0 }
        case SennCmd.transparencyResp, SennCmd.transparencyNotif:
            if let v = p.first { noise.transparencyLevel = v }
        case SennCmd.eqBandResp:
            if p.count >= 2, p[0] < 5 {
                eqBands[Int(p[0])] = Float(Int8(bitPattern: p[1])) / 10
                matchEqPreset()
            }
        case SennCmd.eqNotif:
            if p.count >= 5 {
                for i in 0..<5 { eqBands[i] = Float(Int8(bitPattern: p[i])) / 10 }
                matchEqPreset()
            }
        case SennCmd.bassBoostResp, SennCmd.bassBoostNotif:
            if let v = p.first { bassBoost = v != 0 }
        case SennCmd.batteryResp, SennCmd.batteryNotif:
            if p.count >= 2 { battery = Int(p[1...].max() ?? p[1]) }
            else if let v = p.first { battery = Int(v) }
        case SennCmd.codecResp:
            if let v = p.first { codec = Codec.name(v) }
        case SennCmd.modelIdResp:
            modelId = String(bytes: p.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        case SennCmd.fwVersionResp:
            if p.count >= 6 {
                let a = (Int(p[0]) << 8) | Int(p[1])
                let b = (Int(p[2]) << 8) | Int(p[3])
                let c = (Int(p[4]) << 8) | Int(p[5])
                firmware = "\(a).\(b).\(c)"
            }
        default:
            break
        }
        notify()
    }

    private func matchEqPreset() {
        for preset in EqPreset.all where preset.gains == eqBands {
            eqPreset = preset.name
            return
        }
        if eqBands == EqPreset.bassBoost {
            eqPreset = "Bass Boost"
            return
        }
        eqPreset = "Custom"
    }

    private func fail(_ msg: String) {
        lastError = msg
        if connectionPhase != .connected {
            connectionPhase = .failed
        }
        notify()
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            self.onChange?()
        }
    }
}

extension SennheiserClient {
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard let device else { return }
        if status == kIOReturnSuccess {
            openSerialPortChannel(on: device)
        } else {
            connectionPhase = .failed
            fail("Bluetooth setup failed (error \(status)).")
            scheduleRetry()
        }
    }
}

extension SennheiserClient: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            connectionSucceeded()
            notify()
            refreshAll()
        } else {
            connectionPhase = .failed
            fail("Headphones busy — close Sennheiser Smart Control on your phone.")
            scheduleRetry()
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        let chunk = Data(bytes: dataPointer, count: dataLength)
        rxBuffer.append(contentsOf: chunk)
        let (packets, remainder) = GAIA.split(rxBuffer)
        rxBuffer = remainder
        for pkt in packets { handle(pkt) }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        isConnected = false
        connectionPhase = .idle
        channel = nil
        notify()
        scheduleRetry()
    }
}
