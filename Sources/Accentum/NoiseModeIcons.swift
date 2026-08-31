import SwiftUI

enum NoiseMode {
    case transparency
    case anc
    case off
}

/// Apple Control Center–style noise mode icons (person + arc).
struct NoiseModeIcon: View {
    let mode: NoiseMode

    var body: some View {
        switch mode {
        case .off:
            Image(systemName: "speaker")
                .font(.system(size: 12, weight: .light))
                .symbolRenderingMode(.monochrome)
        case .transparency:
            PersonArcIcon(arcStyle: .dotted)
        case .anc:
            PersonArcIcon(arcStyle: .solid)
        }
    }
}

private struct PersonArcIcon: View {
    enum ArcStyle {
        case solid
        case dotted
    }

    let arcStyle: ArcStyle

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let cx = size.width / 2
            let headRadius = s * 0.115
            let headCenter = CGPoint(x: cx, y: s * 0.36)
            let shoulderRadius = s * 0.34
            let shoulderCenter = CGPoint(x: cx, y: headCenter.y + headRadius * 0.9)
            let arcRadius = headRadius * 1.65
            let color = GraphicsContext.Shading.color(.primary)

            // Head
            let head = Path(
                ellipseIn: CGRect(
                    x: headCenter.x - headRadius,
                    y: headCenter.y - headRadius,
                    width: headRadius * 2,
                    height: headRadius * 2
                )
            )
            context.fill(head, with: color)

            // Shoulders
            var shoulders = Path()
            shoulders.addArc(
                center: shoulderCenter,
                radius: shoulderRadius,
                startAngle: .degrees(200),
                endAngle: .degrees(-20),
                clockwise: false
            )
            shoulders.addLine(to: CGPoint(x: cx, y: size.height))
            shoulders.closeSubpath()
            context.fill(shoulders, with: color)

            // Arc above head
            let arcStart: CGFloat = 205
            let arcEnd: CGFloat = -25
            switch arcStyle {
            case .solid:
                var arc = Path()
                arc.addArc(
                    center: headCenter,
                    radius: arcRadius,
                    startAngle: .degrees(arcStart),
                    endAngle: .degrees(arcEnd),
                    clockwise: false
                )
                context.stroke(
                    arc,
                    with: color,
                    style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round)
                )

            case .dotted:
                let dotCount = 11
                let dotRadius = s * 0.028
                for i in 0..<dotCount {
                    let t = CGFloat(i) / CGFloat(dotCount - 1)
                    let angle = (arcStart + (arcEnd - arcStart) * t) * .pi / 180
                    let point = CGPoint(
                        x: headCenter.x + cos(angle) * arcRadius,
                        y: headCenter.y + sin(angle) * arcRadius
                    )
                    let dot = Path(
                        ellipseIn: CGRect(
                            x: point.x - dotRadius,
                            y: point.y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )
                    )
                    context.fill(dot, with: color)
                }
            }
        }
        .frame(width: 18, height: 18)
    }
}
