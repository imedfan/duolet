import SwiftUI

struct BatteryArc: Shape {
    var fraction: Double
    var leavesPercentageGap = false
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width, rect.height) / 200
        let fraction = min(1, max(0, fraction))
        if leavesPercentageGap {
            // Each side carries half the charge; the number occupies the top gap.
            let center = CGPoint(x: rect.midX, y: rect.midY - 5 * scale)
            let arcs = CGMutablePath()
            if fraction > 0 {
                arcs.addArc(center: center, radius: 77 * scale,
                            startAngle: 150 * .pi / 180,
                            endAngle: (150 + 80 * min(1, fraction * 2)) * .pi / 180, clockwise: false)
            }
            if fraction > 0.5 {
                let rightArc = CGMutablePath()
                rightArc.addArc(center: center, radius: 77 * scale,
                                startAngle: 310 * .pi / 180,
                                endAngle: (310 + 80 * (fraction * 2 - 1)) * .pi / 180, clockwise: false)
                arcs.addPath(rightArc)
            }
            return Path(arcs)
        }
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY - 5 * scale),
                    radius: 77 * scale,
                    startAngle: .degrees(150),
                    endAngle: .degrees(150 + 240 * min(1, max(0, fraction))),
                    clockwise: false)
        return path
    }
}

struct IndicatorView: View {
    let status: DeviceStatus
    var ink: Color = .black
    var inactiveOpacity: Double = 0.19
    var showsPercentage: Bool = false
    var lowBatteryInk: Color? = .red
    static let background = Color(red: 0.90, green: 0.90, blue: 0.91)
    private var inactive: Color { ink.opacity(inactiveOpacity) }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / 200
            let showsReading = showsPercentage && status.power.hasBattery
            ZStack {
                BatteryArc(fraction: 1, leavesPercentageGap: showsReading)
                    .stroke(inactive, style: StrokeStyle(lineWidth: 12 * scale, lineCap: .round))
                if status.power.fraction > 0 {
                    BatteryArc(fraction: status.power.fraction, leavesPercentageGap: showsReading)
                        .stroke(status.power.fraction <= 0.2 ? (lowBatteryInk ?? ink) : ink,
                                style: StrokeStyle(lineWidth: 12 * scale, lineCap: .round))
                }
                if showsReading {
                    Text(status.power.percentage.map { "\($0)" } ?? "—")
                        .font(.system(size: (status.power.percentage == 100 ? 38 : 46) * scale,
                                      weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .position(x: side / 2, y: 30 * scale)
                }
                if status.connection == .wifi {
                    Image(systemName: "wifi")
                        .font(.system(size: 64 * scale, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(ink)
                        .position(x: side / 2, y: 99 * scale)
                } else if status.connection == .ethernet {
                    EthernetMark().fill(ink)
                } else {
                    Image(systemName: status.connection.symbol)
                        .font(.system(size: 57 * scale, weight: .bold))
                        .foregroundStyle(status.connection == .unknown ? inactive : ink)
                        .position(x: side / 2, y: 99 * scale)
                }
                ForEach(0..<4) { index in
                    let x: [CGFloat] = [60, 86, 114, 140]
                    let y: [CGFloat] = [163, 173, 173, 163]
                    Circle()
                        .fill(status.power.isPluggedIn ? ink : inactive)
                        .frame(width: 17 * scale, height: 17 * scale)
                        .position(x: x[index] * scale, y: y[index] * scale)
                }
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
    }
}

/// Apple Ethernet port mark, traced as vectors from the supplied reference.
/// The chevron stroke and the three dots have the same optical thickness.
private struct EthernetMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 200
        let center = CGPoint(x: rect.midX, y: 99 * scale)
        let width = 88 * scale
        let stroke = width * 0.087
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * width, y: center.y + y * width)
        }
        var chevrons = Path()
        chevrons.addLines([point(-0.235, -0.22), point(-0.455, 0), point(-0.235, 0.22)])
        chevrons.move(to: point(0.235, -0.22))
        chevrons.addLine(to: point(0.455, 0))
        chevrons.addLine(to: point(0.235, 0.22))
        var mark = chevrons.strokedPath(StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
        for x in [-0.174, 0, 0.174] {
            let dot = point(x, 0)
            mark.addEllipse(in: CGRect(x: dot.x - stroke / 2, y: dot.y - stroke / 2,
                                       width: stroke, height: stroke))
        }
        return mark
    }
}
