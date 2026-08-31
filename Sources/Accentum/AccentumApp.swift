import SwiftUI
import AppKit

enum AppMode {
    static let isProbe = CommandLine.arguments.contains("--probe")
}

@main
struct AccentumApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
        if AppMode.isProbe {
            Probe.run()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("Accentum", systemImage: "headphones") {
            MenuContentView()
                .environmentObject(coordinator.client)
        }
        .menuBarExtraStyle(.window)
    }
}
