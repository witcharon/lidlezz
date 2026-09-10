import AppKit
import SwiftUI
import LidlezzCore

@MainActor
final class Model: ObservableObject {
    @Published var snap = Snapshot()
    @Published var batteryFloor = Settings.batteryFloor { didSet { Settings.batteryFloor = batteryFloor } }
    @Published var idleMinutes = Settings.idleMinutes { didSet { Settings.idleMinutes = idleMinutes } }
    @Published var autoStart = Settings.autoStart {
        didSet { Settings.autoStart = autoStart; queue.async { self.guardian.autoStart = self.autoStart } }
    }
    @Published var emergency = EmergencyRecord.load()
    @Published var helper = Helper.State.notInstalled
    @Published var hooksInstalled = Hooks.isInstalled()
    @Published var notificationsAllowed = false
    @Published var license = License.status
    @Published var update: (version: String, url: URL)?

    private let guardian = Guardian()
    private let queue = DispatchQueue(label: "lidlezz.guardian")
    private let notifier = Notifier()
    private let onboarding = PanelWindow()
    private let report = PanelWindow()
    private let licenseWindow = PanelWindow()
    private let updater = Updater()

    init() {
        guardian.autoStart = autoStart
        guardian.notify = { [weak self] notice in
            DispatchQueue.main.async { self?.handle(notice) }
        }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.checkEmergency() }
        refresh()
        checkPermissions()
        if !Settings.onboarded { showOnboarding() }
        checkEmergency()
        checkForUpdate()
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdate() }
    }

    // MARK: license and updates

    var isLicensed: Bool { if case .licensed = license { return true }; return false }

    var licenseLine: String {
        switch license {
        case .licensed(let l): return "Licensed to \(l.email)"
        case .trial(let d): return "Trial · \(d) day\(d == 1 ? "" : "s") left · Enter license…"
        case .expired: return "Trial over · Enter license…"
        }
    }

    func showLicense() {
        licenseWindow.show(title: "Lidlezz license", width: 420) { LicenseView().environmentObject(self) }
    }

    func activate(_ key: String) -> Bool {
        guard License.parse(key) != nil else { return false }
        Settings.licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        license = License.status
        licenseWindow.close()
        return true
    }

    private func checkForUpdate() {
        updater.check { [weak self] in self?.update = self?.updater.available }
    }

    // MARK: guarding

    var menuTitle: String { snap.soc.map { String(format: "%.0f°", $0) } ?? "–" }
    var runningFor: String { snap.startedAt.map { Guardian.duration(Date().timeIntervalSince($0)) } ?? "" }

    func setGuarding(_ on: Bool) {
        queue.async { on ? self.guardian.turnOn() : self.guardian.turnOff(byUser: true) }
        refresh()
    }

    func refresh() {
        queue.async {
            let s = self.guardian.tick()
            DispatchQueue.main.async { self.snap = s }
        }
    }

    private func handle(_ notice: Notice) {
        notifier.post(notice)
        if case .emergency = notice { checkEmergency() }
        if case .trialOver = notice { license = License.status; showLicense() }
        refresh()
    }

    // MARK: windows

    func showOnboarding() {
        checkPermissions()
        onboarding.show(title: "Lidlezz", width: 480) { OnboardingView().environmentObject(self) }
    }

    func finishOnboarding() {
        Settings.onboarded = true
        onboarding.close()
    }

    private func checkEmergency() {
        emergency = EmergencyRecord.load()
        guard emergency != nil else { return }
        report.show(title: "Lidlezz", width: 360) { FallbackView().environmentObject(self) }
    }

    func dismissEmergency() {
        EmergencyRecord.clear()
        emergency = nil
        report.close()
    }

    func resumeInTerminal() {
        guard let cmd = emergency?.resumeCommand, let cwd = emergency?.sessions.first?.cwd else { return }
        let script = "tell application \"Terminal\"\nactivate\ndo script \"cd '\(cwd)' && \(cmd)\"\nend tell"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
        dismissEmergency()
    }

    // MARK: setup steps

    private var cliPath: String {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("lidlezz").path
    }

    func checkPermissions() {
        DispatchQueue.global().async {
            let state = Helper.state()
            DispatchQueue.main.async { self.helper = state }
        }
        hooksInstalled = Hooks.isInstalled()
        notifier.isAllowed { self.notificationsAllowed = $0 }
    }

    func installHelper() {
        DispatchQueue.global().async {
            let state = Helper.install()
            DispatchQueue.main.async { self.helper = state }
        }
    }

    func installHooks() { hooksInstalled = Hooks.install(executable: cliPath) }

    func allowNotifications() { notifier.requestPermission { self.notificationsAllowed = $0 } }

    func quit() {
        queue.sync { guardian.turnOff() }
        NSApp.terminate(nil)
    }
}
