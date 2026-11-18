import SwiftUI
import LidlezzCore

/// The menu bar popover: screens 1a (mode on) and 1b (mode off).
struct StatusPanel: View {
    @EnvironmentObject var model: Model
    private var snap: Snapshot { model.snap }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
            cards.padding(.horizontal, 16)
            temperatureBar.padding(.horizontal, 16).padding(.top, 12)
            if !snap.processes.isEmpty { keptAlive }
            if !snap.paused.isEmpty { paused }
            autoStartRow
            manualRow
            batteryFloorRow
            idleRow
            rejoinRow
            OpenAtLoginRow().padding(.horizontal, 16).padding(.top, 10)
            footer
        }
        .frame(width: 360)
        .animation(.easeInOut(duration: 0.2), value: snap.processes.count)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconTile()
            VStack(alignment: .leading, spacing: 1) {
                Text(snap.guarding ? "Staying awake" : "Mac sleeps normally")
                    .font(.system(size: 14, weight: .semibold))
                Text(statusLine).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// For tools that cannot report their own activity. Expires by itself, so it cannot be left on.
    private var manualRow: some View {
        Toggle(model.manualHold ? "Keeping awake by hand · \(model.manualLeft) left"
                                : "Keep awake for \(Int(Model.manualHours)) hours",
               isOn: Binding(get: { model.manualHold }, set: { model.setManualHold($0) }))
            .toggleStyle(.switch).tint(.accentColor).font(.system(size: 13))
            .padding(.horizontal, 16).padding(.top, 10)
    }

    /// Says what is happening now, and what the switch would do.
    private var statusLine: String {
        if model.manualHold { return "By hand · \(model.manualLeft) left" }
        if snap.guarding { return "\(snap.holdReason) · \(model.runningFor)" }
        if let run = snap.lastRun { return "\(snap.holdReason) · last run \(run.summary)" }
        return snap.holdReason
    }

    private var cards: some View {
        let soc = snap.soc ?? 0
        let battery = snap.battery
        return HStack(spacing: 8) {
            StatCard(label: "SoC temp", value: String(format: "%.0f°", soc),
                     valueColor: snap.guarding ? Theme.temperature(soc) : .primary,
                     note: snap.guarding ? "warns at \(Int(Guardian.warnCelsius))°" : "idle")
            StatCard(label: "Battery", value: "\(battery?.percent ?? 0)%",
                     note: snap.guarding ? "sleeps at \(model.batteryFloor)%" : (battery?.onAC == true ? "on AC" : "on battery"))
            StatCard(label: "Power", value: battery?.onAC == true ? "AC" : String(format: "%.1f", battery?.watts ?? 0),
                     unit: battery?.onAC == true ? "" : " W", note: snap.lidMode ? "E-cores only" : "normal")
        }
    }

    private var temperatureBar: some View {
        let soc = snap.soc ?? 0
        let fraction = min(1, max(0, (soc - 40) / 60))
        return VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Theme.temperature(soc)).frame(width: geo.size.width * fraction)
                    marker(at: (Guardian.warnCelsius - 40) / 60, width: geo.size.width)
                    marker(at: (Guardian.sleepCelsius - 40) / 60, width: geo.size.width)
                }
            }
            .frame(height: 6)
            HStack {
                Text("40°"); Spacer()
                Text("\(Int(Guardian.warnCelsius))° warn"); Spacer()
                Text("\(Int(Guardian.sleepCelsius))° sleep")
            }
            .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private func marker(at fraction: Double, width: CGFloat) -> some View {
        Rectangle().fill(Color.primary.opacity(0.4)).frame(width: 1, height: 10).offset(x: width * fraction, y: 0)
    }

    private var keptAlive: some View {
        Section(title: "Kept alive") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(snap.sessions) { s in
                    ProcessRow(pulse: s.working, color: s.waiting ? Theme.orange : Theme.green, name: "claude",
                               detail: s.waiting ? "waiting for the usage limit to reset"
                                   : s.prompt.isEmpty ? s.project : "\(s.prompt) · \(s.toolCalls) tool calls",
                               tag: snap.lidMode ? "bg QoS" : "")
                }
                ForEach(snap.processes.filter { $0.name != "claude" }.prefix(4)) { p in
                    ProcessRow(pulse: false, color: Theme.green, name: p.name, detail: p.args, tag: snap.lidMode ? "bg QoS" : "")
                }
                if snap.sessions.isEmpty && snap.processes.isEmpty {
                    Text("Waiting for Claude Code…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var paused: some View {
        Section(title: "Paused") {
            FlowChips(items: snap.paused)
        }
    }

    private var autoStartRow: some View {
        AutoStartRow().padding(.horizontal, 16).padding(.top, 14)
    }

    private var batteryFloorRow: some View {
        BatteryFloorRow().padding(.horizontal, 16).padding(.top, 14)
    }

    private var idleRow: some View {
        IdleTimeoutRow().padding(.horizontal, 16).padding(.top, 10)
    }

    private var rejoinRow: some View {
        RejoinRow().padding(.horizontal, 16).padding(.top, 10)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Set up…") { model.showOnboarding() }
            Link("Donate", destination: Site.donate)
            if model.canSelfUpdate {
                Button("Check for updates…") { model.checkForUpdateNow() }
            } else if let u = model.updateAvailable {
                Button("Lidlezz \(u) is out · copy brew command") { model.copyBrewCommand() }
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Button("Quit Lidlezz") { model.quit() }
        }
        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .background(Color.black.opacity(0.12))
        .padding(.top, 14)
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var unit = ""
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            (Text(value).font(.system(size: 22, weight: .semibold)).foregroundColor(valueColor)
                + Text(unit).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary))
                .kerning(-0.4)
            Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            SectionLabel(text: title).padding(.top, 4)
            content
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }
}

private struct ProcessRow: View {
    let pulse: Bool
    let color: Color
    let name: String
    let detail: String
    let tag: String
    @State private var dim = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
                .opacity(pulse && dim ? 0.35 : 1)
                .animation(pulse ? .easeInOut(duration: 0.8).repeatForever() : .default, value: dim)
                .onAppear { dim = pulse }
            Text(name).font(Theme.mono)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Text(tag).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// The two settings, shared by the panel and onboarding.
struct AutoStartRow: View {
    @EnvironmentObject var model: Model

    var body: some View {
        Toggle("Stay awake while a coding agent works", isOn: $model.autoStart)
            .toggleStyle(.switch).tint(.accentColor).font(.system(size: 13))
    }
}

struct OpenAtLoginRow: View {
    @EnvironmentObject var model: Model

    var body: some View {
        Toggle("Open at login", isOn: $model.openAtLogin)
            .toggleStyle(.switch).tint(.accentColor).font(.system(size: 13))
    }
}

struct BatteryFloorRow: View {
    @EnvironmentObject var model: Model

    var body: some View {
        SettingSlider(label: "Allow sleep at", value: "\(model.batteryFloor)% battery", range: 5...80,
                      binding: Binding(get: { Double(model.batteryFloor) }, set: { model.batteryFloor = Int($0) }))
    }
}

struct IdleTimeoutRow: View {
    @EnvironmentObject var model: Model

    var body: some View {
        SettingSlider(label: "Allow sleep after", value: "\(model.idleMinutes) min idle", range: 3...30,
                      binding: Binding(get: { Double(model.idleMinutes) }, set: { model.idleMinutes = Int($0) }))
    }
}

/// Which saved hotspot to fall back on. "Never" is the default: no network is touched
/// unless the user names one.
struct RejoinRow: View {
    @EnvironmentObject var model: Model
    static let never = ""

    var body: some View {
        HStack {
            Text("Rejoin when offline").font(.system(size: 13))
            Spacer()
            Picker("", selection: $model.rejoinSSID) {
                Text("Never").tag(Self.never)
                Divider()
                ForEach(model.hotspots, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 190)
        }
        .onAppear { model.loadNetworks() }
    }
}

struct SettingSlider: View {
    let label: String
    let value: String
    let range: ClosedRange<Double>
    let binding: Binding<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13))
                Spacer()
                Text(value).font(.system(size: 13, weight: .medium))
            }
            Slider(value: binding, in: range, step: 1)
        }
    }
}
