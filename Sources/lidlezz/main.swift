import Foundation
import LidlezzCore

let usage = """
lidlezz — keep Claude Code running with the lid closed, without cooking the Mac.

  lidlezz                   lid-closed mode in the terminal (Ctrl-C turns it off)
  lidlezz status            temperature, battery, lid, Claude Code sessions
  lidlezz sensors           every temperature sensor
  lidlezz hooks install     report Claude Code activity to Lidlezz (~/.claude/settings.json)
  lidlezz hooks uninstall
  lidlezz hooks status
  lidlezz helper install    install the background helper that controls sleep (approve it in System Settings)
  lidlezz helper status
  lidlezz battery <percent> turn the mode off when the battery reaches this level (now \(Settings.batteryFloor)%)
  lidlezz idle <minutes>    turn an automatically started mode off after this much idle time (now \(Settings.idleMinutes) min)
  lidlezz license <key>     activate a license (no key: show status)
"""

func line(_ s: Snapshot) -> String {
    let t = s.soc.map { String(format: "%.0f°", $0) } ?? "n/a"
    let b = s.battery.map { "\($0.percent)%\($0.onAC ? " AC" : String(format: " %.1fW", $0.watts))" } ?? "n/a"
    let sessions = s.sessions.map { "\($0.project)\($0.working ? " working" : $0.waiting ? " waiting for limit" : " idle")" }.joined(separator: ", ")
    return "soc \(t)  bat \(b)  lid \(s.lidClosed ? "closed" : "open")  claude \(s.processes.count) procs" +
        (sessions.isEmpty ? "" : "  [\(sessions)]") + (s.lidMode ? "  LID MODE" : s.guarding ? "  guarding" : "") +
        (s.guarding ? "" : s.lastRun.map { "\n  last run: \($0.summary) (\($0.reason))" } ?? "")
}

func executablePath() -> String {
    URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
}

func guardLoop() {
    let guardian = Guardian()
    guardian.notify = { notice in
        let stamp = ISO8601DateFormatter().string(from: Date())
        switch notice {
        case .modeOn: print("\(stamp)  lid-closed mode on" + (Power.hasSleepControl() ? "" : " (helper not ready: lid will still sleep the Mac)"))
        case .warm(let t): print("\(stamp)  ⚠︎ running warm \(Int(t))°")
        case .batteryLow(let p): print("\(stamp)  battery \(p)%, mode turns off at \(Settings.batteryFloor)%")
        case .finished(let why): print("\(stamp)  done: \(why)")
        case .emergency(let why): print("\(stamp)  EMERGENCY: \(why)")
        case .limitWait: print("\(stamp)  usage limit reached, staying awake until it resets")
        case .trialOver: print("\(stamp)  trial over: buy a license at \(Site.buy.absoluteString) and run: lidlezz license <key>")
        case .licenseRevoked: print("\(stamp)  this license was revoked; contact \(Site.base.absoluteString)")
        }
        fflush(stdout)
    }
    signal(SIGINT) { _ in Guardian.terminal?.turnOff(); exit(0) }
    signal(SIGTERM) { _ in Guardian.terminal?.turnOff(); exit(0) }
    Guardian.terminal = guardian
    guardian.autoStart = Settings.autoStart
    guardian.turnOn()
    while guardian.snapshot.guarding {
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
    Sessions.apply(hookPayload: FileHandle.standardInput.readDataToEndOfFile())
case "hooks":
    switch args.dropFirst().first {
    case "install": print(Hooks.install(executable: executablePath()) ? "hooks installed" : "could not write ~/.claude/settings.json")
    case "uninstall": print(Hooks.uninstall() ? "hooks removed" : "could not write ~/.claude/settings.json")
    default: print(Hooks.isInstalled() ? "hooks installed" : "hooks not installed")
    }
case "helper":
    let state = args.dropFirst().first == "install" ? Helper.install() : Helper.state()
    switch state {
    case .ready: print("helper ready")
    case .needsApproval: print("helper installed, approve it: System Settings › General › Login Items › Allow in the Background")
    case .notInstalled: print("helper not installed (lidlezz helper install)")
    case .installedButUnreachable: print("helper enabled but not answering; try again in a moment or reinstall the app")
    }
case "license":
    if let key = args.dropFirst().first {
        if let l = License.parse(key) { Settings.licenseKey = key; print("licensed to \(l.email)") } else { print("invalid license") }
    } else {
        switch License.status {
        case .licensed(let l): print("licensed to \(l.email)")
        case .trial(let d): print("trial, \(d) days left")
        case .expired: print("trial over: \(Site.buy.absoluteString)")
        case .revoked: print("license revoked: \(Site.base.absoluteString)")
        }
    }
case "idle":
    if let m = args.dropFirst().first.flatMap(Int.init), (3...30).contains(m) {
        Settings.idleMinutes = m; print("idle timeout \(m) min")
    } else {
        print("usage: lidlezz idle <3-30>")
    }
case "battery":
    if let p = args.dropFirst().first.flatMap(Int.init), (5...50).contains(p) {
        Settings.batteryFloor = p; print("mode turns off at \(p)%")
    } else { print("usage: lidlezz battery <5-50>") }
default: print(usage)
}
