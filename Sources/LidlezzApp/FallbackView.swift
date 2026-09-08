import SwiftUI
import LidlezzCore

/// Screen 1c: shown after Lidlezz had to turn itself off and put the Mac to sleep.
struct FallbackView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        if let r = model.emergency {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Theme.orange.opacity(0.18)).frame(width: 34, height: 34)
                        .overlay(Image(systemName: "exclamationmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.orange))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lidlezz put your Mac to sleep").font(.system(size: 15, weight: .semibold))
                        Text("\(r.reason) at \(r.endedAt.formatted(date: .omitted, time: .shortened)) while in the bag. Lid-closed mode was turned off first; the session is saved on disk.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(2)
                    }
                }
                .padding(EdgeInsets(top: 18, leading: 16, bottom: 0, trailing: 16))

                VStack(spacing: 8) {
                    row("Peak temp", String(format: "%.0f°", r.peakCelsius), color: Theme.orange)
                    row("Ran with lid closed", Guardian.duration(r.endedAt.timeIntervalSince(r.startedAt)))
                    row("Battery used", "\(r.batteryStart)% → \(r.batteryEnd)%")
                    if let s = r.sessions.first { row("Session", "\(s.project) · \(s.shortID)", mono: true) }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))

                if let cmd = r.resumeCommand {
                    HStack {
                        (Text("$ ").foregroundColor(.secondary) + Text(cmd)).font(Theme.mono)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.accentColor)
                    }
                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    .padding(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Dismiss") { model.dismissEmergency() }
                    Button("Resume in Terminal") { model.resumeInTerminal() }
                        .buttonStyle(.borderedProminent).disabled(r.resumeCommand == nil)
                }
                .padding(16)
            }
        }
    }

    private func row(_ label: String, _ value: String, color: Color = .primary, mono: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).font(mono ? .system(size: 11, design: .monospaced) : .system(size: 12, weight: color == .primary ? .regular : .semibold))
        }
        .font(.system(size: 12))
    }
}
