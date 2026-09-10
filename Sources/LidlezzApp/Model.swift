import AppKit
import Combine
import SwiftUI
import LidlezzCore

@MainActor
final class Model: ObservableObject {
    @Published var snap = Snapshot()
    @Published var batteryFloor = Settings.batteryFloor { didSet { Settings.batteryFloor = batteryFloor } }
    @Published var idleMinutes = Settings.idleMinutes { didSet { Settings.idleMinutes = idleMinutes } }
    @Published var rejoinSSID = Settings.rejoinSSID { didSet { Settings.rejoinSSID = rejoinSSID } }
    @Published var autoStart = Settings.autoStart {
        didSet { Settings.autoStart = autoStart; queue.async { self.guardian.autoStart = self.autoStart } }
    }
    @Published var emergency = EmergencyRecord.load()
    @Published var helper = Helper.State.notInstalled
    @Published var agents: [(agent: Agent, wired: Bool)] = []
    @Published var notificationsAllowed = false
    @Published var license = License.status
    /// Saved hotspots the Mac can rejoin without asking for a password.
    @Published var hotspots: [String] = []

    private let guardian = Guardian()
    private let queue = DispatchQueue(label: "lidlezz.guardian")
    private let notifier = Notifier()
    private let onboarding = PanelWindow()
    private let report = PanelWindow()
    private let licenseWindow = PanelWindow()
    private lazy var updater: Updater = {
        let u = Updater(notifier: notifier)
        u.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        return u
    }()
    private var bag = Set<AnyCancellable>()

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
        loadNetworks()
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdate() }
    }

    // MARK: license and updates

    var isLicensed: Bool { if case .licensed = license { return true }; return false }

    var licenseLine: String {
        switch license {
        case .licensed(let l): return "Licensed to \(l.email)"
        case .trial(let d): return "Trial · \(d) day\(d == 1 ? "" : "s") left · Enter license…"
        case .expired: return "Trial over · Enter license…"
        case .revoked: return "License revoked · Enter license…"
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

    var canSelfUpdate: Bool { updater.canSelfUpdate }

    var updateAvailable: String? { updater.available?.version }

    func checkForUpdateNow() { updater.checkNow() }

    func copyBrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Install.brewUpgradeCommand, forType: .string)
    }

    private func checkForUpdate() {
        updater.check()
        Revocation.refresh { [weak self] in self?.license = License.status }
    }

    // MARK: guarding

    var menuTitle: String { snap.soc.map { String(format: "%.0f°", $0) } ?? "–" }
    var runningFor: String { snap.startedAt.map { Guardian.duration(Date().timeIntervalSince($0)) } ?? "" }

    /// The panel's manual override: keep the Mac awake for a while whatever the agents report.
    static let manualHours = 2.0

    var manualHold: Bool { snap.manualUntil != nil }

    var manualLeft: String {
        snap.manualUntil.map { Guardian.duration($0.timeIntervalSinceNow) } ?? ""
    }

    func setManualHold(_ on: Bool) {
        queue.async {
            on ? self.guardian.holdManually(for: Self.manualHours * 3600) : self.guardian.releaseManual()
            _ = self.guardian.tick()
        }
        refresh()
    }

    /// Re-read them, so a hotspot joined by hand a minute ago is offered here.
    func loadNetworks() {
        DispatchQueue.global().async {
            let found = WiFi.savedHotspots()
            DispatchQueue.main.async {
                let picked = self.rejoinSSID
                self.hotspots = picked.isEmpty || found.contains(picked) ? found : [picked] + found
            }
        }
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
        agents = Agents.present().map { ($0, Agents.isWired($0)) }
        notifier.isAllowed { self.notificationsAllowed = $0 }
    }

    func installHelper() {
        DispatchQueue.global().async {
            let state = Helper.install()
            DispatchQueue.main.async { self.helper = state }
        }
    }

    var hooksInstalled: Bool {
        let wirable = agents.filter { $0.agent.canReportActivity }
        return !wirable.isEmpty && wirable.allSatisfy(\.wired)
    }

    func installHooks() {
        for entry in agents where entry.agent.canReportActivity && !entry.wired {
            Agents.wire(entry.agent, executable: cliPath)
        }
        checkPermissions()
    }

    func wire(_ agent: Agent) {
        Agents.wire(agent, executable: cliPath)
        checkPermissions()
    }

    func allowNotifications() { notifier.requestPermission { self.notificationsAllowed = $0 } }

    func quit() {
        queue.sync {
            guardian.releaseManual()
            guardian.autoStart = false
            _ = guardian.tick()
        }
        NSApp.terminate(nil)
    }
}
