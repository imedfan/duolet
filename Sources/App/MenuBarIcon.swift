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
            // AppKit selects the matching representation when the menu bar moves
            // between displays. Keep the existing Retina drawing at 2× and 3×.
            guard let bitmap = scale == 1
                ? lowResolutionBitmap(status: status, increasedContrast: increasedContrast)
                : standardBitmap(status: status, increasedContrast: increasedContrast, scale: scale)
            else { return nil }
            bitmap.size = image.size
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        image.accessibilityDescription = status.accessibilityLabel
        return image
    }

    private static func standardBitmap(status: DeviceStatus, increasedContrast: Bool, scale: Double) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: IndicatorView(
            status: status, ink: .black, inactiveOpacity: increasedContrast ? 0.5 : 0.3,
            lowBatteryInk: nil
        ).frame(width: size, height: size).environment(\.colorScheme, .light))
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = NSSize(width: size, height: size)
        return bitmap
    }

    /// Optical drawing for a 22-pixel menu icon. Integer bounds keep the power
    /// dots crisp; two-pixel strokes keep the arcs legible on a 1× display.
    /// All colors remain black with alpha so template tinting still works.
    private static func lowResolutionBitmap(status: DeviceStatus, increasedContrast: Bool) -> NSBitmapImageRep? {
        guard let context = CGContext(data: nil, width: 22, height: 22,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let inactive = increasedContrast ? 0.65 : 0.45

        func stroke(_ path: CGPath, width: CGFloat = 2, opacity: Double = 1) {
            context.setStrokeColor(CGColor(gray: 0, alpha: opacity))
            context.setLineWidth(width)
            context.addPath(path)
            context.strokePath()
        }
        func arc(center: CGPoint, radius: CGFloat, start: Double, end: Double) -> CGPath {
            let path = CGMutablePath()
            path.addArc(center: center, radius: radius,
                        startAngle: start * .pi / 180, endAngle: end * .pi / 180, clockwise: false)
            return path
        }
        func line(_ points: [CGPoint], width: CGFloat = 2) {
            let path = CGMutablePath()
            path.addLines(between: points)
            stroke(path, width: width)
        }
        func dot(_ rect: CGRect, opacity: Double = 1) {
            context.setFillColor(CGColor(gray: 0, alpha: opacity))
            context.fillEllipse(in: rect)
        }

        let center = CGPoint(x: 11, y: 10)
        stroke(arc(center: center, radius: 8, start: 150, end: 390), opacity: inactive)
        if status.power.fraction > 0 {
            stroke(arc(center: center, radius: 8, start: 150, end: 150 + 240 * status.power.fraction))
        }
        switch status.connection {
        case .wifi, .offline:
            let wifiCenter = CGPoint(x: 11, y: 14)
            stroke(arc(center: wifiCenter, radius: 6, start: 225, end: 315))
            stroke(arc(center: wifiCenter, radius: 3, start: 225, end: 315))
            dot(CGRect(x: 10, y: 13, width: 2, height: 2))
            if status.connection == .offline {
                // Cut a transparent halo before drawing the slash so it remains
                // distinct where it crosses the two Wi-Fi bands.
                context.saveGState()
                context.setBlendMode(.clear)
                line([CGPoint(x: 7, y: 7), CGPoint(x: 15, y: 15)], width: 3)
                context.restoreGState()
                line([CGPoint(x: 7, y: 7), CGPoint(x: 15, y: 15)], width: 1.5)
            }
        case .ethernet:
            line([CGPoint(x: 8, y: 8.5), CGPoint(x: 6, y: 10.5), CGPoint(x: 8, y: 12.5)], width: 1.5)
            line([CGPoint(x: 14, y: 8.5), CGPoint(x: 16, y: 10.5), CGPoint(x: 14, y: 12.5)], width: 1.5)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            for x in [8, 10, 12] {
                context.fill(CGRect(x: x, y: 10, width: 1, height: 1))
            }
        case .other:
            line([CGPoint(x: 11, y: 9), CGPoint(x: 11, y: 11)], width: 1)
            line([CGPoint(x: 7, y: 13), CGPoint(x: 7, y: 11),
                  CGPoint(x: 15, y: 11), CGPoint(x: 15, y: 13)], width: 1)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(1)
            for (x, y) in [(9.5, 6.5), (5.5, 12.5), (13.5, 12.5)] {
                context.stroke(CGRect(x: x, y: y, width: 3, height: 3))
            }
        case .unknown:
            for x in [6, 10, 14] {
                dot(CGRect(x: x, y: 10, width: 2, height: 2), opacity: inactive)
            }
        }
        for (x, y) in [(5, 17), (8, 18), (12, 18), (15, 17)] {
            dot(CGRect(x: x, y: y, width: 2, height: 2), opacity: status.power.isPluggedIn ? 1 : inactive)
        }
        guard let cgImage = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cgImage)
    }

    static func exportPreviews(to directory: String) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let samples: [(String, DeviceStatus)] = [
            ("wifi-battery", .init(power: .init(percentage: 64, isPluggedIn: false, hasBattery: true), connection: .wifi)),
            ("ethernet-power", .init(power: .init(percentage: 82, isPluggedIn: true, hasBattery: true), connection: .ethernet)),
            ("wifi-full", .preview),
            ("offline-low", .init(power: .init(percentage: 12, isPluggedIn: false, hasBattery: true), connection: .offline)),
            ("battery-empty", .init(power: .init(percentage: 0, isPluggedIn: false, hasBattery: true), connection: .wifi)),
            ("desktop-mac", .init(power: .init(percentage: nil, isPluggedIn: true, hasBattery: false), connection: .ethernet)),
            ("other-network", .init(power: .init(percentage: 50, isPluggedIn: false, hasBattery: true), connection: .other)),
            ("unknown-network", .init(power: .init(percentage: nil, isPluggedIn: false, hasBattery: true), connection: .unknown))
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
            for scale in [1.0, 2.0, 3.0] {
                // Verify AppKit picks the intended representation at each display scale.
                guard let surface = CGContext(data: nil, width: Int(size * scale), height: Int(size * scale),
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw NSError(domain: "Duolet", code: 8)
                }
                surface.scaleBy(x: scale, y: scale)
                let graphics = NSGraphicsContext(cgContext: surface, flipped: false)
                guard icon.bestRepresentation(for: NSRect(x: 0, y: 0, width: size, height: size),
                                              context: graphics, hints: nil)?.pixelsWide == Int(size * scale) else {
                    throw NSError(domain: "Duolet", code: 9,
                                  userInfo: [NSLocalizedDescriptionKey: "Incorrect image representation at \(scale)×"])
                }
                guard let original = standardBitmap(status: status, increasedContrast: false, scale: scale),
                      let originalPNG = original.representation(using: .png, properties: [:]),
                      let updated = icon.representations.compactMap({ $0 as? NSBitmapImageRep })
                        .first(where: { $0.pixelsWide == Int(size * scale) }),
                      let updatedPNG = updated.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "Duolet", code: 4)
                }
                let destination = URL(fileURLWithPath: directory)
                try originalPNG.write(to: destination.appendingPathComponent("\(name)-\(Int(scale))x-before.png"))
                try updatedPNG.write(to: destination.appendingPathComponent("\(name)-\(Int(scale))x-after.png"))
            }
        }
        try exportLowResolutionComparison(samples: samples, to: directory)
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

    private static func exportLowResolutionComparison(samples: [(String, DeviceStatus)], to directory: String) throws {
        for increasedContrast in [false, true] {
            var rows: [(String, CGImage, CGImage)] = []
            for (name, status) in samples {
                guard let before = standardBitmap(status: status, increasedContrast: increasedContrast, scale: 1)?.cgImage,
                      let after = lowResolutionBitmap(status: status, increasedContrast: increasedContrast)?.cgImage else {
                    throw NSError(domain: "Duolet", code: 6)
                }
                rows.append((name, before, after))
            }
            let sheet = HStack(alignment: .top, spacing: 0) {
                ForEach([false, true], id: \.self) { dark in
                    VStack(alignment: .leading, spacing: 16) {
                        Text("1× display · \(increasedContrast ? "increased" : "normal") contrast").font(.headline)
                        Text("Before / after at 22 px, then 6× pixel enlargement").font(.caption)
                        ForEach(rows.indices, id: \.self) { index in
                            HStack(spacing: 16) {
                                Text(rows[index].0).font(.system(size: 11)).frame(width: 100, alignment: .leading)
                                ForEach([false, true], id: \.self) { enlarged in
                                    ForEach([false, true], id: \.self) { updated in
                                        Image(decorative: updated ? rows[index].2 : rows[index].1, scale: 1)
                                            .renderingMode(.template).resizable().interpolation(.none)
                                            .frame(width: enlarged ? 132 : size, height: enlarged ? 132 : size)
                                    }
                                }
                            }
                        }
                    }
                    .padding(24).foregroundStyle(dark ? .white : .black)
                    .background(dark ? Color(white: 0.2) : Color(white: 0.92))
                }
            }
            let renderer = ImageRenderer(content: sheet.environment(\.colorScheme, .light))
            renderer.scale = 1
            guard let cgImage = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "Duolet", code: 7)
            }
            let suffix = increasedContrast ? "-increased-contrast" : ""
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("menu-bar-1x-comparison\(suffix).png"))
        }
    }
}
