import AppKit
import Combine
import Foundation
import IOKit.ps
import Network
import WidgetKit

@MainActor
final class StatusMonitor: ObservableObject {
    @Published private(set) var status = DeviceStatus(power: .read(), connection: .unknown)
    private let network = NWPathMonitor()
    private var powerSource: CFRunLoopSource?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastReload = Date.distantPast

    func start() {
        network.pathUpdateHandler = { [weak self] path in
            let connection = Connection(path: path)
            Task { @MainActor in self?.update(connection: connection) }
        }
        network.start(queue: DispatchQueue(label: "app.duolet.network"))
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<StatusMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.update() }
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.update() } }
        WidgetCenter.shared.reloadTimelines(ofKind: "DuoletWidget")
    }

    func update(connection: Connection? = nil) {
        let next = DeviceStatus(power: .read(), connection: connection ?? status.connection)
        guard next != status else { return }
        let important = next.power.isPluggedIn != status.power.isPluggedIn || next.connection != status.connection
        status = next
        if important || Date.now.timeIntervalSince(lastReload) >= 15 * 60 {
            lastReload = .now
            WidgetCenter.shared.reloadTimelines(ofKind: "DuoletWidget")
        }
    }

    func stop() {
        timer?.invalidate()
        network.cancel()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }
}
