import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps
import CoreGraphics

public struct Battery {
    public let percent: Int
    public let charging: Bool
    public let onAC: Bool
    /// Power drawn from the battery. Zero while on AC.
    public let watts: Double
}

/// Sleep, lid and battery facts plus the root-only pmset/tmutil switches.
public enum Power {
    private static var assertionID: IOPMAssertionID = 0

    public static func holdAwake() {
        guard assertionID == 0 else { return }
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Lidlezz is keeping Claude Code running" as CFString, &assertionID)
    }

    public static func releaseAwake() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private static func registryProperty(_ service: String, _ key: String) -> Any? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(service))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    public static func lidClosed() -> Bool {
        (registryProperty("IOPMrootDomain", "AppleClamshellState") as? Bool) ?? false
    }

    /// Lid closed with a monitor attached is a desk setup, not a bag.
    public static func externalDisplayConnected() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    public static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any],
              let percent = desc[kIOPSCurrentCapacityKey] as? Int
        else { return nil }
        let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let amps = Double((registryProperty("AppleSmartBattery", "InstantAmperage") as? Int) ?? 0)
        let volts = Double((registryProperty("AppleSmartBattery", "Voltage") as? Int) ?? 0)
        let watts = onAC ? 0 : abs(amps) * volts / 1_000_000
        return Battery(percent: percent, charging: (desc[kIOPSIsChargingKey] as? Bool) ?? false,
                       onAC: onAC, watts: watts)
    }

    // MARK: root-only switches, done by the helper daemon

    public static func hasSleepControl() -> Bool { Helper.state() == .ready }
    public static func setSleepDisabled(_ on: Bool) { _ = Helper.setSleepDisabled(on) }
    public static func setLowPowerMode(_ on: Bool) { _ = Helper.setLowPowerMode(on) }
    public static func setTimeMachine(enabled: Bool) { _ = Helper.setTimeMachine(enabled: enabled) }

    public static func sleepNow() {
        Shell.run("/usr/bin/pmset", ["sleepnow"])
    }
}
