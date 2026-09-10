import Foundation

/// One run of lid-closed mode. Saved as the last run at every end, and as the last emergency when
/// Lidlezz forced sleep, shown to the user on the next launch or wake.
public struct EmergencyRecord: Codable {
    public var reason: String
    public var peakCelsius: Double
    public var startedAt: Date
    public var endedAt: Date
    public var batteryStart: Int
    public var batteryEnd: Int
    public var sessions: [Session]

    /// Only Claude Code can be picked up again from the command line, and its id is stored
    /// namespaced ("claude:<uuid>"), so the prefix comes off before the command is shown.
    public var resumeCommand: String? {
        guard let s = sessions.first(where: { ($0.agent ?? "claude") == "claude" }) else { return nil }
        return "claude --resume \(s.id.split(separator: ":").last.map(String.init) ?? s.id)"
    }

    /// "47m · peak 71° · −12% battery"
    public var summary: String {
        let delta = batteryEnd - batteryStart
        return "\(Guardian.duration(endedAt.timeIntervalSince(startedAt))) · peak \(Int(peakCelsius))° · \(delta > 0 ? "+" : "")\(delta)% battery"
    }

    private static let file = AppDir.url.appendingPathComponent("last-emergency.json")
    private static let lastRunFile = AppDir.url.appendingPathComponent("last-run.json")

    public func save() { write(to: Self.file) }
    public func saveAsLastRun() { write(to: Self.lastRunFile) }

    private func write(to url: URL) {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url) }
    }

    public static func loadLastRun() -> EmergencyRecord? {
        guard let data = try? Data(contentsOf: lastRunFile) else { return nil }
        return try? JSONDecoder().decode(EmergencyRecord.self, from: data)
    }

    public static func load() -> EmergencyRecord? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(EmergencyRecord.self, from: data)
    }

    public static func clear() { try? FileManager.default.removeItem(at: file) }
}
