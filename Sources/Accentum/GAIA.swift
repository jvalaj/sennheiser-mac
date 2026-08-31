import Foundation

enum GAIA {
    static let sof: UInt8 = 0xFF
    static let flags: UInt8 = 0x03

    static let vendorSennheiser: UInt16 = 0x0495
    static let vendorQualcomm: UInt16 = 0x001D

    static func frame(vendor: UInt16, command: UInt16, payload: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [sof, flags]
        let len = payload.count
        bytes.append(UInt8((len >> 8) & 0xFF))
        bytes.append(UInt8(len & 0xFF))
        bytes.append(UInt8((vendor >> 8) & 0xFF))
        bytes.append(UInt8(vendor & 0xFF))
        bytes.append(UInt8((command >> 8) & 0xFF))
        bytes.append(UInt8(command & 0xFF))
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    struct Packet {
        let vendor: UInt16
        let command: UInt16
        let payload: [UInt8]
    }

    static func split(_ buffer: [UInt8]) -> (packets: [Packet], remainder: [UInt8]) {
        var packets: [Packet] = []
        var i = 0
        while buffer.count - i >= 8 {
            guard buffer[i] == sof else {
                i += 1
                continue
            }
            let len = (Int(buffer[i + 2]) << 8) | Int(buffer[i + 3])
            let total = 8 + len
            if buffer.count - i < total { break }
            let vendor = (UInt16(buffer[i + 4]) << 8) | UInt16(buffer[i + 5])
            let command = (UInt16(buffer[i + 6]) << 8) | UInt16(buffer[i + 7])
            let payload = Array(buffer[(i + 8)..<(i + total)])
            packets.append(Packet(vendor: vendor, command: command, payload: payload))
            i += total
        }
        return (packets, Array(buffer[i...]))
    }
}

enum SennCmd {
    static let ancModeSet: UInt16 = 0x1A00
    static let ancModeGet: UInt16 = 0x1A01
    static let ancModeResp: UInt16 = 0x1B01
    static let ancModeNotif: UInt16 = 0x1A81

    static let ancOnSet: UInt16 = 0x1A04
    static let ancOnGet: UInt16 = 0x1A05
    static let ancOnResp: UInt16 = 0x1B05
    static let ancOnNotif: UInt16 = 0x1A85

    static let transparencyOnSet: UInt16 = 0x1804
    static let transparencyOnGet: UInt16 = 0x1805
    static let transparencyOnResp: UInt16 = 0x1905
    static let transparencyOnNotif: UInt16 = 0x1885

    static let transparencySet: UInt16 = 0x1A02
    static let transparencyGet: UInt16 = 0x1A03
    static let transparencyResp: UInt16 = 0x1B03
    static let transparencyNotif: UInt16 = 0x1A83

    static let batteryGet: UInt16 = 0x0603
    static let batteryResp: UInt16 = 0x0703
    static let batteryNotif: UInt16 = 0x0683

    static let codecGet: UInt16 = 0x0800
    static let codecResp: UInt16 = 0x0900
    static let modelIdGet: UInt16 = 0x1206
    static let modelIdResp: UInt16 = 0x1306
    static let fwVersionGet: UInt16 = 0x1201
    static let fwVersionResp: UInt16 = 0x1301

    static let eqConfigGet: UInt16 = 0x1000
    static let eqBandSet: UInt16 = 0x1001
    static let eqBandGet: UInt16 = 0x1002
    static let eqBandResp: UInt16 = 0x1102
    static let eqNotif: UInt16 = 0x1082
    static let bassBoostSet: UInt16 = 0x1008
    static let bassBoostGet: UInt16 = 0x1009
    static let bassBoostResp: UInt16 = 0x1109
    static let bassBoostNotif: UInt16 = 0x1089

    static let registerNotification: UInt16 = 0x0007
    static let featureBattery: UInt8 = 3
    static let featureANC: UInt8 = 13
    static let featureUserEQ: UInt8 = 8
}

struct NoiseControlState: Equatable {
    enum Mode: String, CaseIterable {
        case anc = "Noise Cancel"
        case transparency = "Transparency"
        case off = "Off"
        case unknown = "—"

        var icon: String {
            switch self {
            case .anc: return "wave.3.right"
            case .transparency: return "ear"
            case .off: return "speaker"
            case .unknown: return "questionmark"
            }
        }
    }

    var ancOn: Bool?
    var transparencyOn: Bool?
    var transparencyLevel: UInt8 = 0

    var active: Mode {
        if transparencyOn == true { return .transparency }
        if ancOn == true { return .anc }
        if ancOn == false { return .off }
        return .unknown
    }
}

enum EqPreset {
    static let bands = ["50 Hz", "250 Hz", "800 Hz", "3 kHz", "8 kHz"]
    static let all: [(name: String, gains: [Float])] = [
        ("Flat", [0, 0, 0, 0, 0]),
        ("Rock", [0, 0, 3, 3, -1]),
        ("Pop", [0, -5, 0, 5, 0]),
        ("Dance", [2, -3, -3, 1, 1]),
        ("Hip-Hop", [3, -1, -4, 2, 0]),
        ("Classical", [0, 0, 0, 1, 2]),
        ("Movie", [0, 0, 2, 2, -1]),
        ("Jazz", [-3, 0, 2, 2, 0]),
    ]
    static let bassBoost: [Float] = [5, -2, 0, 0, 0]
    static let gainLimit: Float = 6
}

enum Codec {
    static let names: [UInt8: String] = [
        0: "SBC", 1: "AAC", 2: "aptX", 3: "aptX-LL", 4: "MP3", 5: "aptX-HD",
        6: "Faststream", 7: "LHDC", 8: "aptX Adaptive", 9: "aptX Lossless",
        10: "LC3", 255: "—"
    ]
    static func name(_ id: UInt8) -> String { names[id] ?? "0x\(String(id, radix: 16))" }
}
