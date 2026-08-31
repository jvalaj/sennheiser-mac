import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI

final class MediaControls: ObservableObject {
    @Published var volume: Double = 0.5

    private var isDraggingVolume = false
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var outputDeviceListener: AudioObjectPropertyListenerBlock?

    init() {
        refreshVolume()
        installVolumeListener()
    }

    deinit {
        removeVolumeListeners()
    }

    func beginVolumeDrag() {
        isDraggingVolume = true
    }

    func endVolumeDrag() {
        isDraggingVolume = false
    }

    func setVolume(_ value: Double) {
        let clamped = min(1, max(0, value))
        volume = clamped
        SystemVolume.set(clamped)
    }

    func refreshVolume() {
        guard !isDraggingVolume else { return }
        volume = SystemVolume.get()
    }

    private func installVolumeListener() {
        removeVolumeListeners()

        let deviceID = SystemVolume.defaultOutputDeviceID()
        guard deviceID != 0 else { return }

        var address = SystemVolume.volumeAddress()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshVolume()
            }
        }
        volumeListener = block
        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)

        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.installVolumeListener()
                self?.refreshVolume()
            }
        }
        outputDeviceListener = deviceBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            DispatchQueue.main,
            deviceBlock
        )
    }

    private func removeVolumeListeners() {
        if let block = volumeListener {
            let deviceID = SystemVolume.defaultOutputDeviceID()
            if deviceID != 0 {
                var address = SystemVolume.volumeAddress()
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
            }
            volumeListener = nil
        }

        if let block = outputDeviceListener {
            var deviceAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &deviceAddress,
                DispatchQueue.main,
                block
            )
            outputDeviceListener = nil
        }
    }
}

private enum SystemVolume {
    static func defaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func get() -> Double {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != 0 else { return 0.5 }

        var address = volumeAddress()
        guard AudioObjectHasProperty(deviceID, &address) else {
            return averageChannelVolume(deviceID: deviceID) ?? 0.5
        }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { return 0.5 }
        return Double(volume)
    }

    static func set(_ value: Double) {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != 0 else { return }

        let clamped = Float32(min(1, max(0, value)))
        var address = volumeAddress()
        if AudioObjectHasProperty(deviceID, &address) {
            var settable: DarwinBoolean = false
            if AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, settable.boolValue {
                let size = UInt32(MemoryLayout<Float32>.size)
                var volume = clamped
                if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volume) == noErr {
                    return
                }
            }
        }

        setChannelVolume(deviceID: deviceID, value: clamped)
    }

    private static func averageChannelVolume(deviceID: AudioDeviceID) -> Double? {
        let channels = channelVolumes(deviceID: deviceID)
        guard !channels.isEmpty else { return nil }
        return Double(channels.reduce(0, +)) / Double(channels.count)
    }

    private static func channelVolumes(deviceID: AudioDeviceID) -> [Float32] {
        (UInt32(1)...UInt32(2)).compactMap { channel in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: channel
            )
            guard AudioObjectHasProperty(deviceID, &address) else { return nil }
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else { return nil }
            return volume
        }
    }

    private static func setChannelVolume(deviceID: AudioDeviceID, value: Float32) {
        for channel in UInt32(1)...UInt32(2) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: channel
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, settable.boolValue else { continue }
            var volume = value
            let size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volume)
        }
    }
}
