import SwiftUI
import LidlezzCore

/// Two screens: what Lidlezz does and its two settings, then the three permissions it needs.
struct OnboardingView: View {
    @EnvironmentObject var model: Model
    @State private var showingPermissions = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                Image(nsImage: Brand.icon).resizable().frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(showingPermissions ? "Set up Lidlezz" : "Welcome to Lidlezz").font(.system(size: 20, weight: .semibold))
                Text(showingPermissions
                     ? "Keeping a closed Mac awake needs a few system permissions. Each one is removed when you turn the mode off or quit."
                     : "Close the lid while Claude Code works. Lidlezz keeps the Mac awake only as long as needed, and never lets it get hot.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .lineSpacing(3).frame(maxWidth: 360).fixedSize(horizontal: false, vertical: true)
            }
            if showingPermissions { permissions } else { intro }
            HStack {
                Spacer()
                if showingPermissions {
                    Button("Continue") { model.finishOnboarding() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Next") { showingPermissions = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(EdgeInsets(top: 28, leading: 32, bottom: 24, trailing: 32))

    }

    private var intro: some View {
        VStack(spacing: 14) {
            VStack(spacing: 1) {
                feature("bolt.fill", "Awake only while Claude Code works",
                        "Claude Code's hooks report every session. When it finishes, or sits idle for the time you pick below, the Mac sleeps normally.")
                feature("laptopcomputer", "Throttled the moment the lid closes",
                        "Claude Code moves to efficiency cores, Low Power Mode turns on, Photos analysis and Time Machine pause.")
                feature("thermometer.medium", "Watched every 3 seconds",
                        "At 85° it throttles harder. At 95° it saves the session and puts the Mac to sleep.")
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 12) {
                AutoStartRow()
                BatteryFloorRow()
                IdleTimeoutRow()
                RejoinRow()
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.green).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
    }

    private var permissions: some View {
            VStack(spacing: 1) {
                step(done: model.helper == .ready, title: "Sleep control",
                     detail: helperDetail, buttonTitle: model.helper == .needsApproval ? "Open Settings" : "Install",
                     action: model.installHelper)
                step(done: model.hooksInstalled, title: "Coding agents",
                     detail: agentsDetail, buttonTitle: "Connect", action: model.installHooks)
                step(done: model.notificationsAllowed, title: "Notifications",
                     detail: "Temperature warnings and sleep events",
                     action: model.allowNotifications)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Names the tools found on this Mac, so the step says what it is about to touch.
    private var agentsDetail: String {
        let wirable = model.agents.filter { $0.agent.canReportActivity }.map(\.agent.name)
        let manual = model.agents.filter { !$0.agent.canReportActivity }.map(\.agent.name)
        if wirable.isEmpty {
            return manual.isEmpty ? "No coding agents found yet; install one and come back"
                                  : "\(manual.joined(separator: ", ")) has no hook API, so turn the mode on by hand"
        }
        var text = "\(wirable.joined(separator: ", ")) will tell Lidlezz when work starts and finishes"
        if !manual.isEmpty { text += ". \(manual.joined(separator: ", ")): turn the mode on by hand" }
        return text
    }

    private var helperDetail: String {
        switch model.helper {
        case .ready: return "Background helper toggles pmset disablesleep and Low Power Mode"
        case .needsApproval: return "Allow Lidlezz under Login Items › Allow in the Background, then come back"
        case .notInstalled: return "A small background helper toggles pmset disablesleep and Low Power Mode"
        case .installedButUnreachable: return "Helper is enabled but not answering; reinstall the app if this persists"
        }
    }

    private func step(done: Bool, title: String, detail: String, buttonTitle: String = "Allow",
                      action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Circle().strokeBorder(Color.secondary, lineWidth: done ? 0 : 1.5)
                .background(Circle().fill(done ? Theme.green : .clear))
                .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).opacity(done ? 1 : 0))
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if done {
                Text("Installed").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Button(buttonTitle, action: action).controlSize(.small)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
    }
}
