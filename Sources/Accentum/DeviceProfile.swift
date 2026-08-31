import Foundation

struct DeviceProfile {
    let displayName: String
    let transparencySteps: Int
    let hasTransparency: Bool

    static let accentumWireless = DeviceProfile(
        displayName: "ACCENTUM Wireless",
        transparencySteps: 1,
        hasTransparency: true
    )

    static let accentumPlus = DeviceProfile(
        displayName: "ACCENTUM Plus",
        transparencySteps: 3,
        hasTransparency: true
    )

    static let permissive = DeviceProfile(
        displayName: "Sennheiser",
        transparencySteps: 5,
        hasTransparency: true
    )

    var showsTransparencyLevel: Bool { hasTransparency && transparencySteps > 1 }

    static func resolve(modelId: String, name: String) -> DeviceProfile {
        let id = modelId.uppercased()
        let nm = name.uppercased()
        if id.hasPrefix("ACPAEBT") || nm.contains("PLUS") { return accentumPlus }
        if id.hasPrefix("ACAEBT") || nm == "ACCENTUM" || nm.contains("ACCENTUM WIRELESS") {
            return accentumWireless
        }
        return permissive
    }
}
