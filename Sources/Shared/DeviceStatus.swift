import Foundation
import IOKit.ps
import Network

struct PowerStatus: Equatable, Sendable {
    let percentage: Int?
    let isPluggedIn: Bool
    let hasBattery: Bool

    var fraction: Double { Double(min(100, max(0, percentage ?? 0))) / 100 }
    var description: String {
        let charge = hasBattery ? percentage.map { "Battery \($0)%" } ?? "Battery level unknown" : "No built-in battery"
        return charge + (isPluggedIn ? ", external power" : ", battery power")
    }

    static func read() -> PowerStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerStatus(percentage: nil, isPluggedIn: false, hasBattery: true)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return decode(descriptions, externalPower: providing == kIOPSACPowerValue)
    }

    static func decode(_ sources: [[String: Any]], externalPower: Bool) -> PowerStatus {
        guard let battery = sources.first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }) else {
            return PowerStatus(percentage: nil, isPluggedIn: externalPower, hasBattery: false)
        }
        let current = battery[kIOPSCurrentCapacityKey] as? Int
        let maximum = battery[kIOPSMaxCapacityKey] as? Int
        let percentage: Int?
        if let current, let maximum, current >= 0, maximum > 0 {
            percentage = Int((min(1, max(0, Double(current) / Double(maximum))) * 100).rounded())
        } else {
            percentage = nil
        }
        // AC power stays true when charging is paused or the battery is already full.
        let plugged = (battery[kIOPSPowerSourceStateKey] as? String).map { $0 == kIOPSACPowerValue } ?? externalPower
        return PowerStatus(percentage: percentage, isPluggedIn: plugged, hasBattery: true)
    }
}

enum Connection: String, Sendable, CaseIterable {
    case wifi, ethernet, other, offline, unknown

    var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "network" // The indicator draws the supplied Apple Ethernet port mark.
        case .other: "network"
        case .offline: "wifi.slash"
        case .unknown: "ellipsis"
        }
    }
    var description: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .other: "Other connection"
        case .offline: "Disconnected"
        case .unknown: "Checking connection"
        }
    }
    static func resolve(connected: Bool, wired: Bool, wireless: Bool) -> Connection {
        guard connected else { return .offline }
        if wired { return .ethernet }
        if wireless { return .wifi }
        return .other
    }
    init(path: NWPath) {
        self = Self.resolve(connected: path.status == .satisfied,
                            wired: path.usesInterfaceType(.wiredEthernet),
                            wireless: path.usesInterfaceType(.wifi))
    }
}

struct DeviceStatus: Equatable, Sendable {
    var power: PowerStatus
    var connection: Connection
    var accessibilityLabel: String { power.description + ", " + connection.description }
    static let preview = DeviceStatus(power: .init(percentage: 100, isPluggedIn: true, hasBattery: true), connection: .wifi)
}

/// The first NWPathMonitor update is asynchronous; do not read currentPath immediately.
final class NetworkSnapshot: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.duolet.network-snapshot")
    private var completion: ((Connection) -> Void)?

    func read(completion: @escaping (Connection) -> Void) {
        queue.async {
            self.completion = completion
            self.monitor.pathUpdateHandler = { [weak self] path in self?.finish(Connection(path: path)) }
            self.monitor.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 3) { self.finish(.unknown) }
        }
    }

    private func finish(_ connection: Connection) {
        guard let completion else { return }
        self.completion = nil
        monitor.cancel()
        completion(connection)
    }
}
