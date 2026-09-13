import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
struct DuoletApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.indices.contains(index + 1) {
            do {
                try MenuBarIcon.exportPreviews(to: CommandLine.arguments[index + 1])
                try ReleaseArtwork.export(to: CommandLine.arguments[index + 1])
            }
            catch { fputs("\(error)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let semaphore = DispatchSemaphore(value: 0)
            let power = PowerStatus.read()
            let reader = NetworkSnapshot()
            reader.read { connection in
                print(power.description + "; " + connection.description)
                semaphore.signal()
            }
            if semaphore.wait(timeout: .now() + 5) == .timedOut { exit(1) }
            return
        }
        // Opening the executable directly should not create duplicate menu items.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { return }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = StatusMonitor()
    private var item: NSStatusItem!
    private var panel: NSPanel!
    private var stayOnTop: Bool { defaults.bool(forKey: "stayOnTop") }
    private var subscription: AnyCancellable?
    private var accessibilityObserver: NSObjectProtocol?
    private let defaults = UserDefaults.standard
    private var showsPercentage: Bool { defaults.bool(forKey: "showPercentage") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "DuoletStatusItem"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        subscription = monitor.$status.sink { [weak self] status in self?.refreshIcon(status) }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshIcon(self.monitor.status)
            }
        }
        monitor.start()
        if !defaults.bool(forKey: "widgetHidden") { panel.orderFrontRegardless() }
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test"),
           CommandLine.arguments.indices.contains(index + 1) {
            let destination = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                // Exercise the same menu and status item that the user interacts with.
                let menu = makeMenu(settings: false)
                let settingsMenu = makeMenu(settings: true)
                let ethernetMenu = makeMenu(settings: true, connection: .ethernet)
                let offlineMenu = makeMenu(settings: true, connection: .offline)
                let gestureCases: [(NSEvent.EventType, NSEvent.ModifierFlags, Bool)] = [
                    (.leftMouseUp, [], false), (.rightMouseUp, [], false),
                    (.leftMouseUp, [.option], false), (.rightMouseUp, [.option], true),
                    (.rightMouseUp, [.control], false)
                ]
                let gesturesPassed = gestureCases.allSatisfy { type, modifiers, expected in
                    let event = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: modifiers,
                        timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
                    return Self.isSettingsClick(event) == expected
                }
                let originalTitle = item.button?.title
                togglePercentage()
                let percentageChanged = item.button?.title != originalTitle
                togglePercentage()
                let originalVisibility = panel.isVisible
                toggleWidget()
                let visibilityChanged = panel.isVisible != originalVisibility
                toggleWidget()
                let originalFrame = panel.frame
                let originalSizePreference = defaults.object(forKey: "widgetSize")
                var resizePassed = true
                for size in [160, 220, 300] {
                    let row = NSMenuItem()
                    row.representedObject = size
                    resizeWidget(row)
                    resizePassed = resizePassed && Int(panel.frame.width) == size
                }
                panel.setFrame(originalFrame, display: true)
                defaults.set(originalSizePreference, forKey: "widgetSize")
                panel.saveFrame(usingName: "DuoletDesktop")
                let report: [String: Any] = [
                    "bundlePath": Bundle.main.bundlePath,
                    "percentageTogglePassed": percentageChanged && item.button?.title == originalTitle,
                    "widgetVisibilityTogglePassed": visibilityChanged && panel.isVisible == originalVisibility,
                    "widgetSizesPassed": resizePassed,
                    "pid": ProcessInfo.processInfo.processIdentifier,
                    "statusItemVisible": item.isVisible,
                    "desktopWidgetVisible": panel.isVisible,
                    "desktopWidgetWidth": panel.frame.width,
                    "embeddedWidget": FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/Contents/PlugIns/DuoletWidget.appex"),
                    "templateImage": item.button?.image?.isTemplate ?? false,
                    "imageWidth": item.button?.image?.size.width ?? 0,
                    "imageRepresentations": item.button?.image?.representations.count ?? 0,
                    "connection": monitor.status.connection.rawValue,
                    "power": monitor.status.power.description,
                    "menuItems": menu.items.map(\.title),
                    "settingsMenuItems": settingsMenu.items.map(\.title),
                    "ethernetSettingsMenuItems": ethernetMenu.items.map(\.title),
                    "offlineSettingsMenuItems": offlineMenu.items.map(\.title),
                    "optionRightClickCasesPassed": gesturesPassed,
                    "settingsURLs": SettingsDestination.allCases.map { $0.url.absoluteString },
                    "loginEnabled": SMAppService.mainApp.status == .enabled,
                    "ordinaryWindows": NSApplication.shared.windows.filter {
                        $0.isVisible && $0.styleMask.contains(.titled) && $0.level == .normal
                    }.count
                ]
                do {
                    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: URL(fileURLWithPath: destination))
                    if let index = CommandLine.arguments.firstIndex(of: "--capture-ui"),
                       CommandLine.arguments.indices.contains(index + 1) {
                        let directory = CommandLine.arguments[index + 1]
                        let timer = Timer(timeInterval: 1, repeats: false) { [self] _ in
                            MainActor.assumeIsolated { captureWindows(to: directory) }
                        }
                        RunLoop.main.add(timer, forMode: .common)
                    }
                    if CommandLine.arguments.contains("--show-menu"), let button = item.button {
                        statusItemClicked(button)
                    }
                } catch { NSLog("Duolet smoke test: %@", error.localizedDescription) }
            }
        }
    }

    /// Isolated UI snapshots: live SwiftUI panel and the native AppKit menu.
    /// Composite the menu on an opaque surface because backdrop glass is not
    /// available in a view snapshot. Never captures another app or the desktop.
    private func captureWindows(to directory: String) {
        do {
            let destination = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            if let host = panel.contentView as? NSHostingView<DesktopIndicator> {
                var snapshot = host.rootView
                snapshot.snapshot = true
                let renderer = ImageRenderer(content: snapshot
                    .frame(width: panel.frame.width, height: panel.frame.height)
                    .environment(\.colorScheme, .dark))
                renderer.scale = 2
                if let image = renderer.cgImage,
                   let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try data.write(to: destination.appendingPathComponent("desktop-widget.png"))
                }
            }
            for window in NSApplication.shared.windows where window.isVisible && window != panel && window.frame.width > 100 {
                guard let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let glyphs = bitmap.cgImage,
                      let context = CGContext(data: nil, width: glyphs.width, height: glyphs.height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                let bounds = CGRect(x: 0, y: 0, width: glyphs.width, height: glyphs.height)
                context.setFillColor(CGColor(gray: 0.16, alpha: 1))
                context.fill(bounds)
                context.setBlendMode(.normal)
                context.draw(glyphs, in: bounds)
                if let image = context.makeImage(),
                   let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try data.write(to: destination.appendingPathComponent("menu-bar.png"))
                }
            }
        } catch { NSLog("Duolet capture: %@", error.localizedDescription) }
    }

    private func buildPanel() {
        let savedSize = defaults.double(forKey: "widgetSize")
        let size = [160.0, 220.0, 300.0].contains(savedSize) ? savedSize : 220
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Duolet"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        updateLevel()
        panel.contentView = NSHostingView(rootView: DesktopIndicator(monitor: monitor))
        if !panel.setFrameUsingName("DuoletDesktop") {
            if let screen = NSScreen.main {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - size - 28,
                                             y: screen.visibleFrame.maxY - size - 28))
            }
        }
        // Recover a saved position from a monitor that is no longer connected.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.center() }
        panel.setFrameAutosaveName("DuoletDesktop")
    }

    private func refreshIcon(_ status: DeviceStatus) {
        guard let button = item.button else { return }
        if let image = MenuBarIcon.make(status: status, increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast) {
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "battery.0percent", accessibilityDescription: status.accessibilityLabel)
        }
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        button.title = showsPercentage ? status.power.percentage.map { " \($0)%" } ?? " —" : ""
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = "Duolet · " + status.accessibilityLabel
        button.setAccessibilityLabel("Duolet")
        button.setAccessibilityValue(status.accessibilityLabel)
    }

    private static func isSettingsClick(_ event: NSEvent?) -> Bool {
        event?.type == .rightMouseUp && event?.modifierFlags.contains(.option) == true
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        monitor.update()
        let menu = makeMenu(settings: Self.isSettingsClick(NSApplication.shared.currentEvent))
        sender.highlight(true)
        defer { sender.highlight(false) }
        let y = sender.isFlipped ? sender.bounds.maxY + 3 : sender.bounds.minY - 3
        if CommandLine.arguments.contains("--capture-ui") {
            let timer = Timer(timeInterval: 3, target: menu, selector: #selector(NSMenu.cancelTracking), userInfo: nil, repeats: false)
            RunLoop.main.add(timer, forMode: .common)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: y), in: sender)
    }

    private func makeMenu(settings: Bool, connection: Connection? = nil) -> NSMenu {
        let menu = NSMenu(title: "Duolet")
        menu.identifier = NSUserInterfaceItemIdentifier(settings ? "settings" : "standard")
        menu.delegate = self
        menu.autoenablesItems = false
        populateMenu(menu, connection: connection ?? monitor.status.connection)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu, connection: monitor.status.connection)
    }

    private func populateMenu(_ menu: NSMenu, connection: Connection) {
        menu.removeAllItems()
        if menu.identifier?.rawValue == "settings" {
            let destination = SettingsDestination.network(for: connection)
            addSettings(menu, destination)
            addSettings(menu, .battery)
            addSettings(menu, .batteryHealth, enabled: monitor.status.power.hasBattery)
            menu.addItem(.separator())
            add(menu, "Launch at Login", #selector(toggleLogin),
                checked: SMAppService.mainApp.status == .enabled)
            menu.addItem(.separator())
            add(menu, "Quit Duolet", #selector(quit), key: "q")
        } else {
            for title in ["Duolet", monitor.status.power.description, connection.description] {
                let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                row.isEnabled = false
                menu.addItem(row)
            }
            menu.addItem(.separator())
            add(menu, "Show Battery Percentage", #selector(togglePercentage), checked: showsPercentage)
            add(menu, "Launch at Login", #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled)
            add(menu, "Refresh", #selector(refresh))
            menu.addItem(.separator())
            add(menu, panel.isVisible ? "Hide Desktop Widget" : "Show Desktop Widget", #selector(toggleWidget))
            add(menu, "Keep Widget on Top", #selector(toggleLevel), checked: stayOnTop)
            add(menu, "Glass Background", #selector(toggleGlass), checked: !defaults.bool(forKey: "opaqueBackground"))
            let sizes = NSMenuItem(title: "Widget Size", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for (title, size) in [("Small", 160), ("Medium", 220), ("Large", 300)] {
                let row = add(submenu, title, #selector(resizeWidget), checked: Int(panel.frame.width) == size)
                row.representedObject = size
            }
            sizes.submenu = submenu
            menu.addItem(sizes)
            add(menu, "Add System Widget…", #selector(showHelp))
            let hint = NSMenuItem(title: "Option + right-click for settings", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            add(menu, "Quit Duolet", #selector(quit), key: "q")
        }
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        entry.state = checked ? .on : .off
        menu.addItem(entry)
        return entry
    }

    private func addSettings(_ menu: NSMenu, _ destination: SettingsDestination, enabled: Bool = true) {
        let row = add(menu, destination.title, #selector(openSettings(_:)))
        row.representedObject = destination.rawValue
        row.isEnabled = enabled
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let destination = SettingsDestination(rawValue: rawValue) else { return }
        guard NSWorkspace.shared.open(destination.url) else {
            let alert = NSAlert()
            alert.messageText = "Could Not Open System Settings"
            alert.informativeText = "Open the section from Apple menu → System Settings."
            alert.runModal()
            return
        }
    }

    private func updateLevel() {
        panel.level = stayOnTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    @objc private func toggleWidget() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        defaults.set(!panel.isVisible, forKey: "widgetHidden")
    }
    @objc private func toggleLevel() {
        defaults.set(!stayOnTop, forKey: "stayOnTop")
        updateLevel()
        panel.orderFrontRegardless()
        defaults.set(false, forKey: "widgetHidden")
    }
    @objc private func toggleGlass() {
        defaults.set(!defaults.bool(forKey: "opaqueBackground"), forKey: "opaqueBackground")
    }
    @objc private func resizeWidget(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Int else { return }
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - CGFloat(size), width: CGFloat(size), height: CGFloat(size)), display: true)
        defaults.set(size, forKey: "widgetSize")
        panel.saveFrame(usingName: "DuoletDesktop")
    }
    @objc private func togglePercentage() {
        defaults.set(!showsPercentage, forKey: "showPercentage")
        refreshIcon(monitor.status)
    }
    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Change Login Item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Duolet Widgets"
        alert.informativeText = "Right-click the desktop → Edit Widgets → search for Duolet.\n\nThe system widget updates on a macOS schedule. The movable desktop widget updates live while Duolet runs.\n\nThe arc shows battery level. The center shows the active connection. Dim dots mean battery power; solid dots mean external power, including a full battery."
        alert.runModal()
    }
    @objc private func refresh() {
        monitor.update()
        refreshIcon(monitor.status)
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func application(_ application: NSApplication, open urls: [URL]) {
        panel?.orderFrontRegardless()
        defaults.set(false, forKey: "widgetHidden")
        monitor.update()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        panel.saveFrame(usingName: "DuoletDesktop")
        monitor.stop()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if let item { NSStatusBar.system.removeStatusItem(item) }
    }
}

/// Routes are taken from Apple's installed Settings extensions and App Intents.
private enum SettingsDestination: String, CaseIterable {
    case wifi, ethernet, network, battery, batteryHealth

    static func network(for connection: Connection) -> SettingsDestination {
        switch connection {
        case .wifi: .wifi
        case .ethernet: .ethernet
        case .other, .offline, .unknown: .network
        }
    }

    var title: String {
        switch self {
        case .wifi: "Open Wi-Fi Settings…"
        case .ethernet: "Open Ethernet Settings…"
        case .network: "Open Network Settings…"
        case .battery: "Open Battery Settings…"
        case .batteryHealth: "Open Battery Health…"
        }
    }

    var url: URL {
        let route: String
        switch self {
        case .wifi: route = "com.apple.wifi-settings-extension"
        case .ethernet: route = "com.apple.Network-Settings.extension?Ethernet"
        case .network: route = "com.apple.Network-Settings.extension"
        case .battery: route = "com.apple.Battery-Settings.extension"
        case .batteryHealth: route = "com.apple.Battery-Settings.extension?batteryhealth"
        }
        return URL(string: "x-apple.systempreferences:" + route)!
    }
}

private struct DesktopIndicator: View {
    @ObservedObject var monitor: StatusMonitor
    var snapshot = false
    @AppStorage("opaqueBackground") private var opaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false
    var body: some View {
        IndicatorView(status: monitor.status,
                      ink: opaqueBackground ? .black : .primary,
                      inactiveOpacity: contrast == .increased ? 0.45 : 0.24,
                      showsPercentage: isHovered)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
                if opaqueBackground {
                    shape.fill(IndicatorView.background)
                } else if reduceTransparency || snapshot {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else if #available(macOS 26.0, *) {
                    Rectangle().fill(.clear)
                        .glassEffect(.regular, in: shape)
                } else {
                    DesktopBlur().clipShape(shape)
                }
            }
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 28).stroke(.primary.opacity(0.65), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 28))
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: monitor.status.power.fraction)
            .help(monitor.status.accessibilityLabel + "\nDrag to move the widget")
    }
}

private struct DesktopBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
