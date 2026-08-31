import SwiftUI

/// Apple-style EQ curve with draggable band points (5-band hardware layout).
struct EQGraphView: View {
    @Binding var bands: [Float]
    var gainLimit: Float = EqPreset.gainLimit
    var onBandChanged: (Int, Float, Bool) -> Void = { _, _, _ in }
    var onDragActive: (Bool) -> Void = { _ in }

    @State private var activeBand: Int?
    @State private var lastSentGain: Float?

    private let graphHeight: CGFloat = 118
    private let labelHeight: CGFloat = 16
    private let handleSize: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 6) {
                frequencyLabels(width: width)
                ZStack {
                    grid(width: width)
                    curve(width: width)
                    handles(width: width)
                }
                .frame(height: graphHeight)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width))
            }
        }
        .frame(height: labelHeight + graphHeight + 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Equalizer curve")
    }

    // MARK: - Layers

    private func frequencyLabels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(EqPreset.bandFrequencies.indices, id: \.self) { i in
                Text(EqPreset.bandLabels[i])
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(UI.label)
                    .position(x: xPosition(for: i, width: width), y: labelHeight / 2)
            }
        }
        .frame(height: labelHeight)
    }

    private func grid(width: CGFloat) -> some View {
        Canvas { context, canvasSize in
            let midY = canvasSize.height / 2
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: midY))
            zero.addLine(to: CGPoint(x: canvasSize.width, y: midY))
            context.stroke(
                zero,
                with: .color(Color.primary.opacity(0.1)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )

            for i in EqPreset.bandFrequencies.indices {
                let x = xPosition(for: i, width: width)
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(
                    line,
                    with: .color(Color.primary.opacity(0.07)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 5])
                )
            }
        }
    }

    private func curve(width: CGFloat) -> some View {
        let points = bandPoints(width: width, height: graphHeight)
        return Path { path in
            addSmoothCurve(to: &path, through: points)
        }
        .stroke(
            Color.primary.opacity(0.35),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
    }

    private func handles(width: CGFloat) -> some View {
        let points = bandPoints(width: width, height: graphHeight)
        return ZStack {
            ForEach(bands.indices, id: \.self) { i in
                let selected = activeBand == i
                Circle()
                    .fill(Color.primary.opacity(selected ? 0.5 : 0.28))
                    .frame(width: handleSize, height: handleSize)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: selected ? 3 : 1, y: 1)
                    .position(points[i])
                    .animation(.easeOut(duration: 0.12), value: selected)
            }
        }
    }

    // MARK: - Interaction

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeBand == nil {
                    activeBand = nearestBand(to: value.startLocation.x, width: width)
                    onDragActive(true)
                }
                guard let index = activeBand else { return }
                let gain = gain(at: value.location.y, height: graphHeight)
                bands[index] = gain
                if lastSentGain != gain {
                    lastSentGain = gain
                    onBandChanged(index, gain, true)
                }
            }
            .onEnded { _ in
                if let index = activeBand, let gain = lastSentGain {
                    onBandChanged(index, gain, false)
                }
                activeBand = nil
                lastSentGain = nil
                onDragActive(false)
            }
    }

    // MARK: - Geometry

    private func bandPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        bands.indices.map { i in
            CGPoint(
                x: xPosition(for: i, width: width),
                y: yPosition(for: bands[i], height: height)
            )
        }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        let freqs = EqPreset.bandFrequencies
        let minLog = log10(freqs.first!)
        let maxLog = log10(freqs.last!)
        let t = (log10(freqs[index]) - minLog) / (maxLog - minLog)
        return CGFloat(t) * width
    }

    private func yPosition(for gain: Float, height: CGFloat) -> CGFloat {
        let limit = CGFloat(gainLimit)
        let normalized = CGFloat(gain) / limit
        return height / 2 - normalized * (height / 2 - 10)
    }

    private func gain(at y: CGFloat, height: CGFloat) -> Float {
        let limit = CGFloat(gainLimit)
        let normalized = (height / 2 - y) / (height / 2 - 10)
        let clamped = min(max(normalized, -1), 1)
        let stepped = (clamped * limit * 2).rounded() / 2
        return Float(stepped)
    }

    private func nearestBand(to x: CGFloat, width: CGFloat) -> Int {
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in bands.indices {
            let dist = abs(xPosition(for: i, width: width) - x)
            if dist < bestDist {
                bestDist = dist
                best = i
            }
        }
        return best
    }

    private func addSmoothCurve(to path: inout Path, through points: [CGPoint]) {
        guard let first = points.first else { return }
        guard points.count > 1 else {
            path.move(to: first)
            return
        }
        path.move(to: first)
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(points.count - 1, i + 2)]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }
}
