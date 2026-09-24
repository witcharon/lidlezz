import Foundation

public enum Notice {
    case warm(Double)
    case batteryLow(Int)
    case emergency(String)
    case limitWait
    case trialOver
    case licenseRevoked
    case updateAvailable(String)
    case rejoined(String)
}

public struct Snapshot {
    public var soc: Double?
    public var battery: Battery?
    public var lidClosed = false
    public var processes: [ProcessEntry] = []
    public var sessions: [Session] = []
    /// Sleep is being held off right now.
    public var guarding = false
    public var startedAt: Date?
    /// Set while the user asked for the Mac to stay awake regardless of what the agents report.
    public var manualUntil: Date?
    /// Why sleep is held off, for the panel's status line.
    public var holdReason = ""
    public var lidMode = false
    public var paused: [String] = []
    public var online = true

    public init() {}
    public var lastRun: EmergencyRecord?
    public var claudeDetected: Bool { !processes.isEmpty || sessions.contains(where: \.busy) }
    public var busyAgents: [String] {
        Array(Set(sessions.filter(\.busy).map(\.agentName))).sorted()
    }
}

/// Sleep control. There is no mode to switch on: every tick asks one question — should the Mac be
/// allowed to sleep right now — and holds or releases accordingly. An agent that is working (or a
/// manual override) holds sleep off; heat, a flat battery or simple inactivity let it go again.
/// Once the lid closes everything gets throttled, and the guards can force sleep outright.
public final class Guardian {
    public static let warnCelsius = 85.0
    public static let sleepCelsius = 95.0

    public var notify: (Notice) -> Void = { _ in }
    /// Turn on by itself when Claude Code is working (the app sets this from Settings).
    public var autoStart = false
    /// Set by the long-running owner (the app, the terminal loop). A one-shot `status` must not touch sleep.
    public var ownsSleep = false
    public private(set) var snapshot = Snapshot()

    private var manageSleep = false
    /// Last moment an agent reported work. Sleep is held for `idleMinutes` past it, so the Mac does
    /// not drop out from under someone who is about to send the next prompt.
    private var lastBusy: Date?
    private var throttled = Set<Int32>()
    private var peak = 0.0
    private var batteryStart = 0
    private var warnedHot = false
    private var warnedBattery = false
    private var notedLimitWait = false
    private let network = Connectivity()
    private var offlineSince: Date?
    private var lastRejoin: Date?
    private var lastLidSleep = Date.distantPast

    public init() { snapshot.lastRun = EmergencyRecord.loadLastRun() }

    /// Keep the Mac awake no matter what the agents report — for tools with no hook API.
    public func holdManually(for seconds: TimeInterval) {
        guard License.isActive else {
            if case .revoked = License.status { notify(.licenseRevoked) } else { notify(.trialOver) }
            return
        }
        snapshot.manualUntil = Date().addingTimeInterval(seconds)
    }

    public func releaseManual() { snapshot.manualUntil = nil }

    @discardableResult
    public func tick() -> Snapshot {
        snapshot.soc = Thermal.socCelsius()
        snapshot.battery = Power.battery()
        snapshot.lidClosed = Power.lidClosed() && !Power.externalDisplayConnected()
        snapshot.processes = Processes.agentTree()
        Sessions.observe(processes: snapshot.processes)
        snapshot.sessions = Sessions.active()
        snapshot.online = network.isOnline

        if let until = snapshot.manualUntil, until <= Date() { snapshot.manualUntil = nil }
        if snapshot.sessions.contains(where: \.busy) { lastBusy = Date() }

        let wanted = shouldHold()
        if wanted && !snapshot.guarding { startHold() }
        if !wanted && snapshot.guarding {
            let danger = snapshot.holdReason.hasPrefix("Battery") || snapshot.holdReason.hasPrefix("SoC")
            let lidWasClosed = snapshot.lidClosed
            stopHold(reason: snapshot.holdReason)
            if danger && lidWasClosed { forceSleep(snapshot.holdReason) }
        }
        if snapshot.guarding { holdTick() } else if ownsSleep { letSleep() }
        return snapshot
    }

    /// The whole policy, in one place.
    private func shouldHold() -> Bool {
        guard License.isActive else { snapshot.holdReason = "no licence"; return false }

        if let b = snapshot.battery, !b.charging, b.percent <= Settings.batteryFloor {
            snapshot.holdReason = "Battery reached \(b.percent)%"
            return false
        }
        if (snapshot.soc ?? 0) >= Self.sleepCelsius {
            snapshot.holdReason = "SoC reached \(Int(snapshot.soc ?? 0))°"
            return false
        }
        if let until = snapshot.manualUntil, until > Date() {
            snapshot.holdReason = "kept awake by hand"
            return true
        }
        guard autoStart else { snapshot.holdReason = "automatic hold is off"; return false }

        let busy = snapshot.busyAgents
        if !busy.isEmpty {
            snapshot.holdReason = busy.joined(separator: ", ") + " working"
            return true
        }
        // Nothing is working now: keep the Mac up a little longer in case the next prompt is coming.
        if let last = lastBusy, Date().timeIntervalSince(last) < Double(Settings.idleMinutes) * 60 {
            let left = Double(Settings.idleMinutes) * 60 - Date().timeIntervalSince(last)
            snapshot.holdReason = "idle, \(Int(left / 60) + 1) min left"
            return true
        }
        snapshot.holdReason = snapshot.claudeDetected ? "no agent is working" : "no agent running"
        return false
    }

    private func startHold() {
        manageSleep = Power.hasSleepControl()
        peak = 0; warnedHot = false; warnedBattery = false; notedLimitWait = false
        offlineSince = nil; lastRejoin = nil
        batteryStart = snapshot.battery?.percent ?? 0
        snapshot.guarding = true
        snapshot.startedAt = Date()
        Power.holdAwake()
        if manageSleep { Power.setSleepDisabled(true) }
    }

    private func stopHold(reason: String) {
        let record = record(reason)
        record.saveAsLastRun()
        snapshot.lastRun = record
        leaveLidMode()
        if manageSleep { Power.setSleepDisabled(false) }
        Power.releaseAwake()
        snapshot.guarding = false
        snapshot.startedAt = nil
    }

    /// Not holding: make sure nothing still keeps the Mac up that should not. macOS decides lid sleep
    /// only at the moment the lid shuts; if we were holding then, nothing re-checks once we let go,
    /// and a Mac in a bag stays awake until the battery is flat. So a closed lid gets put to sleep here.
    private func letSleep() {
        if Power.sleepDisabled() && Power.hasSleepControl() { Power.setSleepDisabled(false) }
        guard snapshot.lidClosed || onlyClaudeAppKeepsAwake(),
              Date().timeIntervalSince(lastLidSleep) > 60 else { return }
        lastLidSleep = Date()
        Power.sleepNow()
    }

    /// Lid open: the Claude app holds idle sleep off for as long as it runs, even with nothing to do.
    /// Once it is the only thing left in the way (the display already off, nothing else playing or
    /// busy), sleep as macOS would have, unless its sleep timer says never.
    private func onlyClaudeAppKeepsAwake() -> Bool {
        Power.idleSleepBlockers() == ["Claude"] && Power.idleSleepMinutes() > 0
    }

    private func holdTick() {
        let soc = snapshot.soc ?? 0
        peak = max(peak, soc)

        let waiting = snapshot.sessions.contains(where: \.waiting)
        if waiting, !notedLimitWait { notedLimitWait = true; notify(.limitWait) }
        if !waiting { notedLimitWait = false }

        if soc >= Self.warnCelsius, !warnedHot { warnedHot = true; notify(.warm(soc)) }
        if soc < Self.warnCelsius - 5 { warnedHot = false }
        if let b = snapshot.battery, !b.charging, b.percent <= Settings.batteryFloor + 5, !warnedBattery {
            warnedBattery = true; notify(.batteryLow(b.percent))
        }

        rejoinTick()

        if snapshot.lidClosed { enterLidMode() } else { leaveLidMode() }
    }

    /// Off the network with a hotspot saved: join it again. macOS gets a grace period to do it
    /// itself first, and a failed attempt is not repeated for a minute.
    private func rejoinTick() {
        let ssid = Settings.rejoinSSID
        guard !ssid.isEmpty else { return }
        guard !snapshot.online else {
            offlineSince = nil
            // Only ours to report: coming back on the home Wi-Fi by itself is not a rejoin.
            if lastRejoin != nil { lastRejoin = nil; notify(.rejoined(ssid)) }
            return
        }
        let now = Date()
        let since = offlineSince ?? now
        offlineSince = since
        guard now.timeIntervalSince(since) >= 15 else { return }
        guard now.timeIntervalSince(lastRejoin ?? .distantPast) >= 60 else { return }
        lastRejoin = now
        WiFi.join(ssid)
    }

    private func record(_ reason: String) -> EmergencyRecord {
        EmergencyRecord(reason: reason, peakCelsius: peak, startedAt: snapshot.startedAt ?? Date(), endedAt: Date(),
                        batteryStart: batteryStart, batteryEnd: snapshot.battery?.percent ?? 0,
                        sessions: snapshot.sessions)
    }

    /// Heat or a flat battery with the lid shut: save the session and put the Mac to sleep for real.
    private func forceSleep(_ reason: String) {
        record(reason).save()
        snapshot.manualUntil = nil
        notify(.emergency(reason))
        lastLidSleep = Date()
        Power.sleepNow()
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
