import Foundation

public enum Notice {
    case modeOn
    case warm(Double)
    case batteryLow(Int)
    case finished(String)
    case emergency(String)
    case limitWait
    case trialOver
    case licenseRevoked
}

public struct Snapshot {
    public var soc: Double?
    public var battery: Battery?
    public var lidClosed = false
    public var processes: [ProcessEntry] = []
    public var sessions: [Session] = []
    public var guarding = false
    public var startedAt: Date?
    public var lidMode = false
    public var paused: [String] = []

    public init() {}
    public var lastRun: EmergencyRecord?
    public var claudeDetected: Bool { !processes.isEmpty || sessions.contains(where: \.busy) }
}

/// Lid-closed mode. Holds the Mac awake while Claude Code works, throttles everything once the
/// lid closes, and gives up before heat or battery become a problem.
public final class Guardian {
    public static let warnCelsius = 85.0
    public static let sleepCelsius = 95.0

    public var notify: (Notice) -> Void = { _ in }
    /// Turn on by itself when Claude Code is working (the app sets this from Settings).
    public var autoStart = false
    public private(set) var snapshot = Snapshot()

    private var manageSleep = false
    private var startedAutomatically = false
    /// Set when the user turns the mode off while Claude Code is still running, so auto-start
    /// does not flip it straight back on. Cleared once Claude Code is gone.
    private var autoStartSuppressed = false
    private var throttled = Set<Int32>()
    private var peak = 0.0
    private var batteryStart = 0
    private var warnedHot = false
    private var warnedBattery = false
    private var notedLimitWait = false
    private var idleSince: Date?

    public init() { snapshot.lastRun = EmergencyRecord.loadLastRun() }

    public func turnOn(automatically: Bool = false) {
        guard !snapshot.guarding else { return }
        guard License.isActive else {
            if !automatically {
                if case .revoked = License.status { notify(.licenseRevoked) } else { notify(.trialOver) }
            }
            autoStartSuppressed = true
            return
        }
        manageSleep = Power.hasSleepControl()
        startedAutomatically = automatically
        peak = 0; warnedHot = false; warnedBattery = false; notedLimitWait = false; idleSince = nil
        batteryStart = Power.battery()?.percent ?? 0
        snapshot.guarding = true
        snapshot.startedAt = Date()
        Power.holdAwake()
        if manageSleep { Power.setSleepDisabled(true) }
        notify(.modeOn)
    }

    public func turnOff(byUser: Bool = false, reason: String = "turned off") {
        guard snapshot.guarding else { return }
        if byUser { autoStartSuppressed = true }
        let record = record(reason)
        record.saveAsLastRun()
        snapshot.lastRun = record
        leaveLidMode()
        if manageSleep { Power.setSleepDisabled(false) }
        Power.releaseAwake()
        snapshot.guarding = false
        snapshot.startedAt = nil
    }

    @discardableResult
    public func tick() -> Snapshot {
        snapshot.soc = Thermal.socCelsius()
        snapshot.battery = Power.battery()
        snapshot.lidClosed = Power.lidClosed() && !Power.externalDisplayConnected()
        snapshot.processes = Processes.claudeTree()
        snapshot.sessions = Sessions.active()

        if !snapshot.claudeDetected { autoStartSuppressed = false }
        if snapshot.guarding { guardTick() } else if autoStart && !autoStartSuppressed && shouldAutoStart {
            turnOn(automatically: true)
        }
        return snapshot
    }

    /// Only a session the hooks report as busy starts the mode; an idle `claude` at its prompt does not.
    /// Never below the battery floor, otherwise the floor turns it off and this turns it back on.
    private var shouldAutoStart: Bool {
        guard snapshot.sessions.contains(where: \.busy) else { return false }
        if let b = snapshot.battery, !b.charging, b.percent <= Settings.batteryFloor { return false }
        return true
    }

    private func guardTick() {
        let soc = snapshot.soc ?? 0
        let battery = snapshot.battery
        let working = snapshot.sessions.contains(where: \.busy)
        peak = max(peak, soc)

        let waiting = snapshot.sessions.contains(where: \.waiting)
        if waiting, !notedLimitWait { notedLimitWait = true; notify(.limitWait) }
        if !waiting { notedLimitWait = false }

        if soc >= Self.sleepCelsius { emergency("SoC reached \(Int(soc))°"); return }
        if let b = battery, !b.charging, b.percent <= Settings.batteryFloor {
            emergency("Battery reached \(b.percent)%"); return
        }
        if soc >= Self.warnCelsius, !warnedHot { warnedHot = true; notify(.warm(soc)) }
        if soc < Self.warnCelsius - 5 { warnedHot = false }
        if let b = battery, !b.charging, b.percent <= Settings.batteryFloor + 5, !warnedBattery {
            warnedBattery = true; notify(.batteryLow(b.percent))
        }

        if snapshot.processes.isEmpty && !working {
            finish("claude exited"); return
        }
        if startedAutomatically && !working {
            idleSince = idleSince ?? Date()
            if Date().timeIntervalSince(idleSince!) > Double(Settings.idleMinutes) * 60 { finish("Claude Code is idle"); return }
        } else {
            idleSince = nil
        }

        if snapshot.lidClosed { enterLidMode() } else { leaveLidMode() }
    }

    private func record(_ reason: String) -> EmergencyRecord {
        EmergencyRecord(reason: reason, peakCelsius: peak, startedAt: snapshot.startedAt ?? Date(), endedAt: Date(),
                        batteryStart: batteryStart, batteryEnd: snapshot.battery?.percent ?? 0,
                        sessions: snapshot.sessions)
    }

    private func finish(_ why: String) {
        turnOff(reason: why)
        notify(.finished("\(why) · \(snapshot.lastRun?.summary ?? ""). Mac will sleep normally."))
    }

    private func emergency(_ reason: String) {
        record(reason).save()
        let lidWasClosed = snapshot.lidClosed
        autoStartSuppressed = true
        turnOff(reason: reason)
        notify(.emergency(reason))
        if lidWasClosed { Power.sleepNow() }
    }

    private func enterLidMode() {
        let pids = Set(snapshot.processes.map(\.pid))
        if !snapshot.lidMode {
            snapshot.lidMode = true
            if manageSleep {
                Power.setLowPowerMode(true)
                Power.setTimeMachine(enabled: false)
            }
            snapshot.paused = Processes.setPaused(true)
                + (manageSleep ? ["Time Machine", "Low Power Mode on"] : [])
        }
        let fresh = pids.subtracting(throttled)
        Processes.setBackground(fresh, true)
        throttled.formUnion(fresh)
    }

    private func leaveLidMode() {
        guard snapshot.lidMode else { return }
        snapshot.lidMode = false
        snapshot.paused = []
        Processes.setBackground(throttled.intersection(snapshot.processes.map(\.pid)), false)
        throttled.removeAll()
        _ = Processes.setPaused(false)
        if manageSleep {
            Power.setLowPowerMode(false)
            Power.setTimeMachine(enabled: true)
        }
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
    }
}
