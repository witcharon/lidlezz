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

    /// `pmset disablesleep`, whoever set it.
    public static func sleepDisabled() -> Bool {
        (registryProperty("IOPMrootDomain", "SleepDisabled") as? Bool) ?? false
    }

    /// Processes holding an idle Mac or its display awake. While the display is on, powerd is one of them.
    public static func idleSleepBlockers() -> Set<String> {
        let types: Set<String> = ["PreventUserIdleSystemSleep", "NoIdleSleepAssertion",
                                  "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let all = byProcess?.takeRetainedValue() as? [AnyHashable: [[String: Any]]] else { return [] }
        return Set(all.values.joined().compactMap { a in
            types.contains(a["AssertType"] as? String ?? "") ? a["Process Name"] as? String : nil
        })
    }

    /// The idle sleep timer for the current power source, in minutes; 0 means never.
    public static func idleSleepMinutes() -> Int { pmsetSetting("sleep") ?? 0 }

    public static func lowPowerMode() -> Bool { pmsetSetting("lowpowermode") == 1 }

    /// One value from `pmset -g`, for the current power source.
    private static func pmsetSetting(_ key: String) -> Int? {
        for line in Shell.run("/usr/bin/pmset", ["-g"]).output.split(separator: "\n") {
            let words = line.split(separator: " ")
            if words.count > 1, words[0] == key { return Int(words[1]) }
        }
        return nil
    }

    /// Automatic backups are on. Unknown (the file can be unreadable) counts as on.
    public static func timeMachineAutoBackup() -> Bool {
        NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.TimeMachine.plist")?["AutoBackup"] as? Bool ?? true
    }

    /// Lid closed with a monitor attached is a desk setup, not a bag. Asked of the hardware: with the
    /// lid shut and nothing plugged in, WindowServer puts up a stand-in display that CoreGraphics
    /// reports as external, which read as a desk and kept a Mac in a bag awake all night. A real
    /// monitor shows up as an external framebuffer with a display attached.
    public static func externalDisplayConnected() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"),
                                           &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        var sawFramebuffer = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            sawFramebuffer = true
            let external = IORegistryEntryCreateCFProperty(entry, "external" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool ?? false
            let attached = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() != nil
            if external && attached { return true }
        }
        return sawFramebuffer ? false : cgExternalDisplay()
    }

    /// Intel Macs have no IOMobileFramebufferShim; fall back to what CoreGraphics lists.
    private static func cgExternalDisplay() -> Bool {
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
