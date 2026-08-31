import Foundation
import IOBluetooth
import Combine

final class SennheiserClient: NSObject, ObservableObject {
    enum ConnectionPhase: Equatable {
        case idle, connecting, disconnecting, connected, wired, failed
    }

    private(set) var deviceName: String = ""
    private(set) var isConnected = false
    private(set) var connectionPhase: ConnectionPhase = .idle
    private(set) var modelId: String = ""
    private(set) var firmware: String = ""
    private(set) var battery: Int?
    private(set) var batteryIsCharging = false
    private(set) var codec: String = "—"
    private(set) var noise = NoiseControlState()
    private(set) var lastError: String = ""

    var profile: DeviceProfile { DeviceProfile.resolve(modelId: modelId, name: deviceName) }

    private(set) var eqBands: [Float] = [0, 0, 0, 0, 0]
    private(set) var eqPreset: String = "Flat"
    private(set) var bassBoost = false
    /// `true` = music keeps playing in transparency; `false` = automatic pause (factory default).
    private(set) var transparencyKeepsMusic: Bool?

    private(set) var wiredAudioDeviceName: String?
    /// User opted in to Bluetooth while headphones are on USB audio.
    private var userRequestedBluetooth = false

    var isWiredUSBActive: Bool { wiredAudioDeviceName != nil }

    /// USB-C audio without GAIA — show the wired prompt instead of disabled controls.
    var showsWiredBluetoothPrompt: Bool {
        isWiredUSBActive && !showsNoiseControlOptions && connectionPhase != .disconnecting
    }

    /// Noise rows visible while connecting or connected (avoids wired prompt flash during BT switch).
    var showsNoiseControlOptions: Bool {
        isConnected || connectionPhase == .connecting
    }

    var isConnectingBluetooth: Bool {
        connectionPhase == .connecting
    }

    var showsBatteryStatus: Bool {
        isConnected || isWiredUSBActive || connectionPhase == .wired || connectionPhase == .disconnecting
    }

    var effectiveBatteryIsCharging: Bool {
        if isWiredUSBActive { return true }
        return batteryIsCharging
    }

    var onChange: (() -> Void)?

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var rxBuffer: [UInt8] = []
    private var connectionTimeout: DispatchWorkItem?
    private var retryTimer: Timer?
    private var connectGeneration = 0
    private let ioQueue = DispatchQueue(label: "accentum.gaia.io", qos: .userInitiated)
    private var modeStepWork: DispatchWorkItem?
    private let bluetoothDisconnector = BluetoothDisconnector()

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

    static func connectedAccentumDevices() -> [IOBluetoothDevice] {
        candidateDevices().filter { $0.isConnected() }
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

    /// User chose USB-C — close GAIA and disconnect Bluetooth.
    func preferWired() {
        userRequestedBluetooth = false
        cancelTimers()
        connectGeneration += 1

        channel?.close()
        channel = nil
        isConnected = false
        rxBuffer.removeAll()
        device = nil

        let btDevices = Self.connectedAccentumDevices()
        guard !btDevices.isEmpty else {
            applyWiredPreference()
            return
        }

        connectionPhase = .disconnecting
        lastError = ""
        notify()

        bluetoothDisconnector.disconnectAll(btDevices) { [weak self] in
            self?.applyWiredPreference()
        }
    }

    private func applyWiredPreference() {
        if isWiredUSBActive {
            enterWiredMode()
        } else {
            connectionPhase = .idle
            lastError = ""
            notify()
        }
    }

    var isDisconnectingBluetooth: Bool {
        connectionPhase == .disconnecting
    }

    var canSwitchToWired: Bool {
        guard isWiredUSBActive, connectionPhase != .disconnecting else { return false }
        return isBluetoothLinked || isConnected || connectionPhase == .connecting
    }

    /// User tapped Connect / Connect Bluetooth — may open a BT session even when USB audio is active.
    func connectBluetooth() {
        userRequestedBluetooth = true
        connectionPhase = .connecting
        lastError = ""
        notify()
        connectBluetoothNow()
    }

    /// Automatic GAIA hookup (launch, BT reconnect). Skipped while on USB-C unless the user opted in.
    func autoConnectBluetoothIfNeeded() {
        guard shouldAcceptBluetoothAutoConnect() else { return }
        guard let connected = Self.connectedAccentum() else { return }
        connect(to: connected)
    }

    func connectFirstAvailable() {
        connectBluetooth()
    }

    private func connectBluetoothNow() {
        cancelRetryTimer()
        reconcileStaleGAIA()

        if let connected = Self.connectedAccentum() {
            connect(to: connected)
            return
        }
        if let first = Self.candidateDevices().first {
            if !first.isConnected() {
                connectionPhase = .connecting
                deviceName = first.name ?? first.addressString ?? "Sennheiser"
                lastError = ""
                notify()
                ioQueue.async { [weak self] in
                    let result = first.openConnection()
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard self.userRequestedBluetooth else { return }
                        if result == kIOReturnSuccess || first.isConnected() {
                            self.connect(to: first)
                        } else {
                            self.connectionPhase = .failed
                            self.fail("Couldn't connect Bluetooth. Check System Settings → Bluetooth.")
                        }
                    }
                }
                return
            }
            connect(to: first)
            return
        }
        if isWiredUSBActive {
            enterWiredMode()
            return
        }
        connectionPhase = .failed
        fail("No paired Accentum found. Pair in System Settings → Bluetooth.")
        scheduleRetry()
    }

    /// Refresh state when the menu opens — never forces Bluetooth while on USB audio.
    func refreshOnMenuOpen() {
        reconcileStaleGAIA()
        guard !isConnected else { return }
        if connectionPhase == .connecting { return }
        if prefersWiredOnly {
            enterWiredMode()
            return
        }
        autoConnectBluetoothIfNeeded()
    }

    func syncWiredAudio(deviceName name: String?) {
        let wasWired = isWiredUSBActive
        wiredAudioDeviceName = name

        if prefersWiredOnly {
            if connectionPhase == .connecting {
                connectGeneration += 1
            }
            enterWiredMode()
            return
        }

        if wasWired, connectionPhase == .wired, !isWiredUSBActive, !isConnected {
            connectionPhase = .idle
            notify()
        }
    }

    func shouldAcceptBluetoothAutoConnect() -> Bool {
        connectionPhase != .disconnecting && (!isWiredUSBActive || userRequestedBluetooth)
    }

    private var prefersWiredOnly: Bool {
        isWiredUSBActive && !userRequestedBluetooth
    }

    private func reconcileStaleGAIA() {
        guard isConnected, !isBluetoothLinked else { return }
        channel?.close()
        channel = nil
        isConnected = false
        if isWiredUSBActive {
            enterWiredMode()
        } else {
            connectionPhase = .idle
            notify()
        }
    }

    private func enterWiredMode() {
        cancelTimers()
        channel?.close()
        channel = nil
        isConnected = false
        userRequestedBluetooth = false
        connectionPhase = .wired
        lastError = ""
        if deviceName.isEmpty {
            deviceName = wiredAudioDeviceName ?? "Accentum"
        }
        codec = "USB"
        notify()
    }

    private func shouldAttemptBluetoothReconnect() -> Bool {
        userRequestedBluetooth || !isWiredUSBActive
    }

    var isBluetoothLinked: Bool {
        Self.connectedAccentum() != nil
    }

    func disconnect() {
        cancelTimers()
        connectGeneration += 1
        channel?.close()
        channel = nil
        device = nil
        isConnected = false
        if connectionPhase == .disconnecting {
            // preferWired() owns the transition — let it finish.
            rxBuffer.removeAll()
            notify()
            return
        }
        if isWiredUSBActive {
            enterWiredMode()
        } else {
            connectionPhase = .idle
        }
        rxBuffer.removeAll()
        notify()
    }

    private func clearDeviceState() {
        battery = nil
        batteryIsCharging = false
        modelId = ""
        firmware = ""
        codec = "—"
        noise = NoiseControlState()
        eqBands = [0, 0, 0, 0, 0]
        eqPreset = "Flat"
        bassBoost = false
        transparencyKeepsMusic = nil
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
        guard shouldAttemptBluetoothReconnect() else { return }
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.retryTimer = nil
            guard let self, !self.isConnected else { return }
            self.autoConnectBluetoothIfNeeded()
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
        let work = { [weak self] in
            guard let self, let ch = self.channel, self.isConnected else { return }
            let data = GAIA.frame(vendor: vendor, command: command, payload: payload)
            var frame = [UInt8](data)
            frame.withUnsafeMutableBytes { raw in
                _ = ch.writeSync(raw.baseAddress, length: UInt16(raw.count))
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func sendOnIO(vendor: UInt16 = GAIA.vendorSennheiser, _ command: UInt16, _ payload: [UInt8] = []) {
        send(vendor: vendor, command, payload)
    }

    private func refreshEssentials() {
        send(SennCmd.registerNotification, [SennCmd.featureANC])
        send(SennCmd.registerNotification, [SennCmd.featureBattery])
        send(SennCmd.ancOnGet)
        send(SennCmd.transparencyOnGet)
        send(SennCmd.batteryGet)
        send(SennCmd.codecGet)
    }

    private func refreshSecondary() {
        send(SennCmd.registerNotification, [SennCmd.featureUserEQ])
        send(SennCmd.modelIdGet)
        send(SennCmd.fwVersionGet)
        send(SennCmd.transparencyGet)
        send(SennCmd.transparencyHearingModeGet)
        send(SennCmd.eqConfigGet)
        for b in UInt8(0)..<5 { send(SennCmd.eqBandGet, [b]) }
        send(SennCmd.bassBoostGet)
    }

    private func refreshAll() {
        refreshEssentials()
        refreshSecondary()
    }

    private func refreshAllStaggered() {
        refreshEssentials()
        let delay: TimeInterval = 0.04
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refreshSecondary()
        }
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

    private func sendModeSteps(_ steps: [(UInt16, [UInt8])]) {
        let gap: TimeInterval = steps.count > 1 ? 0.35 : 0
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + gap * Double(i)) { [weak self] in
                self?.send(step.0, step.1)
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
        for (i, g) in gains.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) { [weak self] in
                self?.sendEqBand(i, g, immediate: true)
            }
        }
    }

    func setEqBand(_ index: Int, _ gain: Float, live: Bool = false) {
        guard eqBands.indices.contains(index) else { return }
        eqBands[index] = gain
        eqPreset = "Custom"
        notify()
        sendEqBand(index, gain, immediate: !live)
    }

    func setBassBoost(_ on: Bool) {
        bassBoost = on
        notify()
        send(SennCmd.bassBoostSet, [on ? 1 : 0])
        send(SennCmd.bassBoostGet)
    }

    private var eqWork: [Int: DispatchWorkItem] = [:]
    private func sendEqBand(_ index: Int, _ gainDB: Float, immediate: Bool = false) {
        eqWork[index]?.cancel()
        let raw = Int8(clamping: Int((gainDB * 10).rounded()))
        let payload: [UInt8] = [UInt8(index), UInt8(bitPattern: raw)]
        let fire: () -> Void = { [weak self] in
            self?.send(SennCmd.eqBandSet, payload)
        }
        if immediate {
            fire()
            return
        }
        let work = DispatchWorkItem(block: fire)
        eqWork[index] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func setTransparencyKeepsMusic(_ keepsMusic: Bool) {
        transparencyKeepsMusic = keepsMusic
        notify()
        // 0x00 = keep music playing, 0x01 = automatic pause (mute music)
        send(SennCmd.transparencyHearingModeSet, [keepsMusic ? 0 : 1])
        send(SennCmd.transparencyHearingModeGet)
    }

    func applyTransparencyMusicPreferenceIfNeeded() {
        if transparencyKeepsMusic != true {
            setTransparencyKeepsMusic(true)
        }
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
        case SennCmd.transparencyHearingModeResp:
            if let v = p.first { transparencyKeepsMusic = v == 0 }
        case SennCmd.eqBandResp:
            if p.count >= 2, p[0] < 5 {
                eqBands[Int(p[0])] = Float(Int8(bitPattern: p[1])) / 10
                matchEqPreset()
            } else if p.count == 1 {
                // GET band response is a single signed gain byte (dB×10).
                // We don't track which band was requested; notifications refresh all bands.
            }
        case SennCmd.eqNotif:
            if p.count >= 5 {
                for i in 0..<5 { eqBands[i] = Float(Int8(bitPattern: p[i])) / 10 }
                matchEqPreset()
            }
        case SennCmd.bassBoostResp, SennCmd.bassBoostNotif:
            if let v = p.first { bassBoost = v != 0 }
        case SennCmd.batteryResp, SennCmd.batteryNotif:
            parseBatteryPayload(p)
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

    private func parseBatteryPayload(_ p: [UInt8]) {
        guard !p.isEmpty else { return }

        if p.count == 2, p[1] <= 100, p[0] <= 1 {
            batteryIsCharging = p[0] == 1
            battery = Int(p[1])
            return
        }

        let levels = p.filter { $0 <= 100 }.map(Int.init)
        if let level = levels.max() {
            battery = level
        } else if let v = p.first {
            battery = Int(v)
        }

        if p.count >= 2, p[0] <= 1 {
            batteryIsCharging = p[0] == 1
        }
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
            refreshAllStaggered()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.applyTransparencyMusicPreferenceIfNeeded()
            }
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
        channel = nil
        if isWiredUSBActive, !isBluetoothLinked {
            enterWiredMode()
        } else {
            connectionPhase = .idle
            notify()
            scheduleRetry()
        }
    }
}
