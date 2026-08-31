import Foundation

enum Support {
    static let email = "jvalajpandey13@gmail.com"

    static func bugReportURL(
        deviceName: String,
        firmware: String,
        model: String,
        connected: Bool
    ) -> URL {
        let body = """
        
        
        ---
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        App: Accentum
        Connected: \(connected ? "yes" : "no")
        Headphones: \(deviceName.isEmpty ? "—" : deviceName)
        Model: \(model)
        Firmware: \(firmware.isEmpty ? "—" : firmware)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Accentum Bug Report"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? URL(string: "mailto:\(email)")!
    }
}
