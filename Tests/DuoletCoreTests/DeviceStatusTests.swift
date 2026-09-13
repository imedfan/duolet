import XCTest
import IOKit.ps
@testable import DuoletCore

final class DeviceStatusTests: XCTestCase {
    private func battery(_ current: Int, _ max: Int = 100, plugged: Bool = false, charging: Bool = false) -> [String: Any] {
        [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: current,
         kIOPSMaxCapacityKey: max, kIOPSPowerSourceStateKey: plugged ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
         kIOPSIsChargingKey: charging]
    }
    func testCapacityIsNormalizedAndClamped() {
        XCTAssertEqual(PowerStatus.decode([battery(2400, 4000)], externalPower: false).percentage, 60)
        XCTAssertEqual(PowerStatus.decode([battery(110)], externalPower: false).percentage, 100)
        XCTAssertEqual(PowerStatus.decode([battery(0)], externalPower: false).percentage, 0)
    }
    func testInvalidCapacityDoesNotLookLikeFullBattery() {
        XCTAssertNil(PowerStatus.decode([battery(20, 0)], externalPower: false).percentage)
        XCTAssertNil(PowerStatus.decode([battery(-1)], externalPower: false).percentage)
    }
    func testPausedChargingStillShowsBlackDots() {
        let full = PowerStatus.decode([battery(100, plugged: true, charging: false)], externalPower: true)
        let paused = PowerStatus.decode([battery(80, plugged: true, charging: false)], externalPower: true)
        XCTAssertTrue(full.isPluggedIn)
        XCTAssertTrue(paused.isPluggedIn)
        XCTAssertFalse(PowerStatus.decode([battery(80)], externalPower: false).isPluggedIn)
    }
    func testExternalAccessoriesAreNotMacBattery() {
        let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSCurrentCapacityKey: 99, kIOPSMaxCapacityKey: 100]
        let status = PowerStatus.decode([ups, battery(42)], externalPower: false)
        XCTAssertEqual(status.percentage, 42)
        let desktop = PowerStatus.decode([ups], externalPower: true)
        XCTAssertFalse(desktop.hasBattery)
        XCTAssertNil(desktop.percentage)
        XCTAssertTrue(desktop.isPluggedIn)
    }
    func testMissingStateFallsBackToSystemPowerSource() {
        var source = battery(60)
        source.removeValue(forKey: kIOPSPowerSourceStateKey)
        XCTAssertTrue(PowerStatus.decode([source], externalPower: true).isPluggedIn)
    }
    func testDisconnectedStateHasExplicitSlashedWifiSymbol() {
        let connection = Connection.resolve(connected: false, wired: false, wireless: false)
        XCTAssertEqual(connection.symbol, "wifi.slash")
        XCTAssertEqual(connection.description, "Disconnected")
    }
    func testNetworkUsesActivePathAndPrefersWired() {
        XCTAssertEqual(Connection.resolve(connected: true, wired: true, wireless: true), .ethernet)
        XCTAssertEqual(Connection.resolve(connected: true, wired: false, wireless: true), .wifi)
        XCTAssertEqual(Connection.resolve(connected: false, wired: true, wireless: true), .offline)
        XCTAssertEqual(Connection.resolve(connected: true, wired: false, wireless: false), .other)
    }
}
