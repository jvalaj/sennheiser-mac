import SwiftUI

enum ConnectionRoute {
    case wired
    case bluetooth
}

struct CCConnectionRouteIcon: View {
    let route: ConnectionRoute
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: fontSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .frame(width: size, height: size)
    }

    private var symbolName: String {
        switch route {
        case .wired: "cable.connector"
        case .bluetooth: "bluetooth"
        }
    }

    private var fontSize: CGFloat {
        max(9, size * 0.78)
    }
}
