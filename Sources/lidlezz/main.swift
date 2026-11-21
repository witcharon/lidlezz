import AppKit
import LidlezzCore

let usage = """
lidlezz — keep Claude Code running with the lid closed, without cooking the Mac.

  lidlezz                   lid-closed mode in the terminal (Ctrl-C turns it off)
  lidlezz status            temperature, battery, lid, Claude Code sessions
  lidlezz sensors           every temperature sensor
  lidlezz agents            which coding agents are installed and connected
  lidlezz hooks install     connect every agent found (or: hooks install cursor)
  lidlezz hooks uninstall
  lidlezz helper install    install the background helper that controls sleep (approve it in System Settings)
  lidlezz helper status
  lidlezz battery <percent> turn the mode off when the battery reaches this level (now \(Settings.batteryFloor)%)
  lidlezz idle <minutes>    turn an automatically started mode off after this much idle time (now \(Settings.idleMinutes) min)
"""

func line(_ s: Snapshot) -> String {
    let t = s.soc.map { String(format: "%.0f°", $0) } ?? "n/a"
    let b = s.battery.map { "\($0.percent)%\($0.onAC ? " AC" : String(format: " %.1fW", $0.watts))" } ?? "n/a"
    let sessions = s.sessions.map { "\($0.label)\($0.working ? " working" : $0.waiting ? " waiting for limit" : " idle")" }.joined(separator: ", ")
    return "soc \(t)  bat \(b)  lid \(s.lidClosed ? "closed" : "open")  agents \(s.processes.count) procs" +
        (sessions.isEmpty ? "" : "  [\(sessions)]") + (s.lidMode ? "  LID MODE" : s.guarding ? "  guarding" : "") +
        (s.guarding ? "  \(s.holdReason)" : s.lastRun.map { "\n  last run: \($0.summary) (\($0.reason))" } ?? "")
}

func executablePath() -> String {
    URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
}

func guardLoop() {
    // Two owners of sleep undo each other: the app would release what this loop holds.
    guard NSRunningApplication.runningApplications(withBundleIdentifier: HelperIdentity.appBundleID).isEmpty else {
        print("Lidlezz is already running in the menu bar: use \"Keep awake\" in its panel, or quit it first.")
        exit(1)
    }
    let guardian = Guardian()
    guardian.notify = { notice in
        let stamp = ISO8601DateFormatter().string(from: Date())
        switch notice {
        case .warm(let t): print("\(stamp)  ⚠︎ running warm \(Int(t))°")
        case .batteryLow(let p): print("\(stamp)  battery \(p)%, mode turns off at \(Settings.batteryFloor)%")
        case .emergency(let why): print("\(stamp)  EMERGENCY: \(why)")
        case .limitWait: print("\(stamp)  usage limit reached, staying awake until it resets")
        case .updateAvailable(let v): print("\(stamp)  Lidlezz \(v) is out")
        case .rejoined(let ssid): print("\(stamp)  back online on \(ssid)")
        case .sleepStuck: print("\(stamp)  sleep is switched off and the helper isn't answering: run lidlezz helper install, or \(Helper.releaseSleepCommand)")
        }
        fflush(stdout)
    }
    signal(SIGINT) { _ in Guardian.terminal?.shutdown(); exit(0) }
    signal(SIGTERM) { _ in Guardian.terminal?.shutdown(); exit(0) }
    Guardian.terminal = guardian
    guardian.autoStart = Settings.autoStart
    guardian.ownsSleep = true
    // In the terminal the command itself is the request: hold until Ctrl-C.
    guardian.holdManually(for: .greatestFiniteMagnitude)
    if !Power.hasSleepControl() { print("helper not ready: the lid will still sleep the Mac") }
    while true {
        print(line(guardian.tick())); fflush(stdout)
        Thread.sleep(forTimeInterval: 5)
    }
}

extension Guardian {
    /// Reachable from C signal handlers.
    static var terminal: Guardian?
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case nil: guardLoop()
case "status": print(line(Guardian().tick()))
case "sensors":
    for s in Thermal.sensors().sorted(by: { $0.celsius > $1.celsius }) {
        print(String(format: "%6.1f°  %@", s.celsius, s.name))
    }
case "hook":
    // lidlezz hook <agent> [event] [json]   — Codex passes its JSON as the last argument,
    // everyone else pipes it on stdin.
    let rest = Array(args.dropFirst())
    let agent = rest.first ?? ""
    let tail = rest.dropFirst()
    let inline = tail.last.flatMap { $0.hasPrefix("{") ? $0.data(using: .utf8) : nil }
    let event = inline == nil ? (tail.first ?? "") : (tail.count > 1 ? tail.first! : "")
    Sessions.apply(agent: agent, event: event,
                   payload: inline ?? FileHandle.standardInput.readDataToEndOfFile())
case "hooks", "agents":
    let action = args.dropFirst().first
    let named = args.dropFirst(2).first.flatMap(Agents.agent)
    let targets = named.map { [$0] } ?? Agents.present().filter(\.canReportActivity)
    switch action {
    case "install":
        for a in targets {
            let ok = Agents.wire(a, executable: executablePath())
            print("  \(ok ? "connected" : "could not connect") \(a.name)" +
                  "")
        }
    case "uninstall":
        for a in targets { print("  \(Agents.unwire(a) ? "disconnected" : "could not disconnect") \(a.name)") }
    default:
        for a in Agents.present() {
            let state = a.canReportActivity ? (Agents.isWired(a) ? "connected" : "not connected")
                                            : "no hook API, turn the mode on by hand"
            print("  \(a.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(state)")
        }
    }
case "helper":
    let state = args.dropFirst().first == "install" ? Helper.install() : Helper.state()
    switch state {
    case .ready: print("helper ready")
    case .needsApproval: print("helper installed, approve it: System Settings › General › Login Items › Allow in the Background")
    case .notInstalled: print("helper not installed (lidlezz helper install)")
    case .installedButUnreachable: print("helper enabled but not answering; repair it with: lidlezz helper install")
    }
case "idle":
    if let m = args.dropFirst().first.flatMap(Int.init), (3...30).contains(m) {
        Settings.idleMinutes = m; print("idle timeout \(m) min")
    } else {
        print("usage: lidlezz idle <3-30>")
    }
case "battery":
    if let p = args.dropFirst().first.flatMap(Int.init), Settings.batteryFloorRange.contains(p) {
        Settings.batteryFloor = p; print("mode turns off at \(p)%")
    } else { print("usage: lidlezz battery <\(Settings.batteryFloorRange.lowerBound)-\(Settings.batteryFloorRange.upperBound)>") }
default: print(usage)
}
