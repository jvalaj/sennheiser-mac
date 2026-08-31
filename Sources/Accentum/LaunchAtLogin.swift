import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let key = "launchAtLogin"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            setEnabled(newValue)
        }
    }

    static func applySavedPreference() {
        setEnabled(isEnabled)
    }

    private static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Login item may fail in unsigned dev builds — non-fatal.
        }
    }
}
