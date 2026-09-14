import AppKit
import SwiftUI

/// Reproducible artwork made from the same indicator as the running app.
@MainActor
enum ReleaseArtwork {
    static func export(to directory: String) throws {
        let destination = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.34, green: 0.72, blue: 0.68),
                                               Color(red: 0.07, green: 0.26, blue: 0.33)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            IndicatorView(status: .preview, ink: .white, inactiveOpacity: 0.25)
                .padding(140)
        }.padding(24).frame(width: 1024, height: 1024)
        try save(icon, to: destination.appendingPathComponent("app-icon.png"))
        let states: [(String, DeviceStatus)] = [
            ("Wi-Fi · on battery", .init(power: .init(percentage: 64, isPluggedIn: false, hasBattery: true), connection: .wifi)),
            ("Ethernet · plugged in", .init(power: .init(percentage: 82, isPluggedIn: true, hasBattery: true), connection: .ethernet)),
            ("Disconnected · 12%", .init(power: .init(percentage: 12, isPluggedIn: false, hasBattery: true), connection: .offline))
        ]
        let sheet = VStack(alignment: .leading, spacing: 32) {
            Text("Duolet").font(.system(size: 48, weight: .semibold, design: .rounded))
            Text("One quiet place for power & connection.")
                .font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 28) {
                ForEach(0..<states.count, id: \.self) { index in
                    VStack(spacing: 20) {
                        IndicatorView(status: states[index].1, ink: .white, inactiveOpacity: 0.25)
                            .padding(22).frame(width: 210, height: 210)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 32))
                            .overlay(RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.12)))
                        Text(states[index].0).font(.system(size: 15, weight: .medium))
                    }
                }
            }
            Text("Menu bar + desktop widget + WidgetKit").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(56).foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.07, green: 0.20, blue: 0.23), Color(red: 0.03, green: 0.07, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        try save(sheet, to: destination.appendingPathComponent("indicator-states.png"), scale: 2)
        let percentageStates: [(String, DeviceStatus)] = [
            ("50", .init(power: .init(percentage: 50, isPluggedIn: true, hasBattery: true), connection: .wifi)),
            ("16", .init(power: .init(percentage: 16, isPluggedIn: true, hasBattery: true), connection: .wifi)),
            ("100", .preview),
            ("0", .init(power: .init(percentage: 0, isPluggedIn: false, hasBattery: true), connection: .offline)),
            ("Ethernet", .init(power: .init(percentage: 82, isPluggedIn: true, hasBattery: true), connection: .ethernet)),
            ("Unknown", .init(power: .init(percentage: nil, isPluggedIn: false, hasBattery: true), connection: .unknown)),
            ("No battery", .init(power: .init(percentage: nil, isPluggedIn: true, hasBattery: false), connection: .ethernet))
        ]
        let percentageSheet = VStack(alignment: .leading, spacing: 20) {
            ForEach([160, 220, 300], id: \.self) { size in
                Text("\(size) pt widget · battery percentage").font(.headline)
                HStack(spacing: 12) {
                    ForEach(percentageStates.indices, id: \.self) { index in
                        VStack {
                            IndicatorView(status: percentageStates[index].1, showsPercentage: true)
                                .padding(16).frame(width: CGFloat(size), height: CGFloat(size))
                            Text(percentageStates[index].0).font(.caption)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                IndicatorView(status: percentageStates[0].1)
                    .padding(16).frame(width: 220, height: 220)
                IndicatorView(status: percentageStates[1].1, ink: .white, inactiveOpacity: 0.28,
                              showsPercentage: true, lowBatteryInk: nil)
                    .padding(16).frame(width: 220, height: 220).background(Color.black)
                Text("Percentage off · monochrome appearance").font(.headline)
            }
        }
        .padding(24).foregroundStyle(.black).background(IndicatorView.background)
        try save(percentageSheet, to: destination.appendingPathComponent("percentage-states.png"), scale: 2)
    }

    private static func save<V: View>(_ view: V, to url: URL, scale: Double = 1) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = scale
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Duolet.Artwork", code: 1)
        }
        try png.write(to: url)
    }
}
