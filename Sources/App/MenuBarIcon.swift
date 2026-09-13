import AppKit
import SwiftUI

@MainActor
enum MenuBarIcon {
    static let size: CGFloat = 22

    /// Transparent template images let AppKit adapt the glyph to the menu bar,
    /// including dark wallpapers, highlighted menus, and Liquid Glass.
    static func make(status: DeviceStatus, increasedContrast: Bool) -> NSImage? {
        let image = NSImage(size: NSSize(width: size, height: size))
        for scale in [1.0, 2.0, 3.0] {
            let renderer = ImageRenderer(content: IndicatorView(
                status: status, ink: .black, inactiveOpacity: increasedContrast ? 0.5 : 0.3
            ).frame(width: size, height: size).environment(\.colorScheme, .light))
            renderer.scale = scale
            guard let cgImage = renderer.cgImage else { return nil }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            bitmap.size = image.size
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        image.accessibilityDescription = status.accessibilityLabel
        return image
    }

    static func exportPreviews(to directory: String) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let samples: [(String, DeviceStatus)] = [
            ("wifi-battery", .init(power: .init(percentage: 64, isPluggedIn: false, hasBattery: true), connection: .wifi)),
            ("ethernet-power", .init(power: .init(percentage: 82, isPluggedIn: true, hasBattery: true), connection: .ethernet)),
            ("wifi-full", .preview),
            ("offline-low", .init(power: .init(percentage: 12, isPluggedIn: false, hasBattery: true), connection: .offline)),
            ("battery-empty", .init(power: .init(percentage: 0, isPluggedIn: false, hasBattery: true), connection: .wifi)),
            ("desktop-mac", .init(power: .init(percentage: nil, isPluggedIn: true, hasBattery: false), connection: .ethernet))
        ]
        for (name, status) in samples {
            guard let icon = make(status: status, increasedContrast: false) else {
                throw NSError(domain: "Duolet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render icon"])
            }
            // Export the exact 2× menu-bar image, not a separate approximation.
            guard let bitmap = icon.representations.compactMap({ $0 as? NSBitmapImageRep }).first(where: { $0.pixelsWide == 44 }),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "Duolet", code: 2)
            }
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + "-22pt.png"))
        }
        let sheet = VStack(alignment: .leading, spacing: 20) {
            Text("Duolet").font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Your Mac, at a glance.").font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 18) {
                    Text("Finder").fontWeight(.semibold)
                    Spacer()
                    ForEach(0..<3) { index in
                        Image(nsImage: make(status: samples[index].1, increasedContrast: false)!)
                            .renderingMode(.template)
                            .frame(width: size, height: size)
                    }
                    Text("12:41").fontWeight(.medium)
                }
                .font(.system(size: 13))
                .foregroundStyle(dark ? .white : .black)
                .padding(.horizontal, 16).frame(height: 38)
                .background(dark ? Color(white: 0.15) : Color(white: 0.9), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 28) {
                ForEach(0..<3) { index in
                    VStack(spacing: 10) {
                        IndicatorView(status: samples[index].1, inactiveOpacity: 0.3)
                            .frame(width: 100, height: 100)
                        Text(["Wi-Fi · 64%", "Ethernet · 82%", "Wi-Fi · 100%"][index])
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }.frame(maxWidth: .infinity)
            Text("Enlarged detail · dim dots: battery, solid dots: external power")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 460).background(Color(white: 0.97))
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Duolet", code: 3)
        }
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("menu-bar-preview.png"))
    }
}
