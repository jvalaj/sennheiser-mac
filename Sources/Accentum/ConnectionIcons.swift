import SwiftUI

// MARK: - Vector connection icons (16×16 viewBox)

struct USBCIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        let ox = rect.midX - 8 * s
        let oy = rect.midY - 8 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        var path = Path()
        path.move(to: p(5.5, 3))
        path.addLine(to: p(10.5, 3))
        path.addLine(to: p(11.5, 5))
        path.addLine(to: p(11.5, 11))
        path.addLine(to: p(10.5, 13))
        path.addLine(to: p(5.5, 13))
        path.addLine(to: p(4.5, 11))
        path.addLine(to: p(4.5, 5))
        path.closeSubpath()

        path.move(to: p(6.5, 6))
        path.addLine(to: p(9.5, 6))
        path.move(to: p(6.5, 8.5))
        path.addLine(to: p(9.5, 8.5))
        path.move(to: p(6.5, 11))
        path.addLine(to: p(9.5, 11))
        return path
    }
}

struct BluetoothIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        let ox = rect.midX - 8 * s
        let oy = rect.midY - 8 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        var path = Path()
        path.move(to: p(7.5, 3))
        path.addLine(to: p(7.5, 13))
        path.move(to: p(7.5, 3))
        path.addLine(to: p(11.5, 7))
        path.addLine(to: p(8.5, 8))
        path.addLine(to: p(11.5, 9))
        path.addLine(to: p(7.5, 13))
        path.move(to: p(7.5, 8))
        path.addLine(to: p(4.5, 5.5))
        path.move(to: p(7.5, 8))
        path.addLine(to: p(4.5, 10.5))
        return path
    }
}

enum ConnectionRoute {
    case wired
    case bluetooth
}

struct CCConnectionRouteIcon: View {
    let route: ConnectionRoute
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch route {
            case .wired:
                USBCIcon()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            case .bluetooth:
                BluetoothIcon()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}
