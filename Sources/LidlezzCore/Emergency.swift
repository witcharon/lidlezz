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
        guard let s = claudeSession else { return nil }
        return "claude --resume \(Shell.quoted(s.id.split(separator: ":").last.map(String.init) ?? s.id))"
    }

    /// The same, from that session's own directory.
    public var resumeInDirectoryCommand: String? {
        guard let s = claudeSession, let resume = resumeCommand else { return nil }
        return s.cwd.isEmpty ? resume : "cd \(Shell.quoted(s.cwd)) && \(resume)"
    }

    private var claudeSession: Session? { sessions.first { ($0.agent ?? "claude") == "claude" } }

    /// "47m · peak 71° · −12% battery"
    public var summary: String {
        let delta = batteryEnd - batteryStart
        return "\(Guardian.duration(endedAt.timeIntervalSince(startedAt))) · peak \(Int(peakCelsius))° · \(delta > 0 ? "+" : "")\(delta)% battery"
    }

    private static let file = AppDir.url.appendingPathComponent("last-emergency.json")
    private static let lastRunFile = AppDir.url.appendingPathComponent("last-run.json")
    /// Every run, one JSON object per line. macOS rotates its own power logs within a week,
    /// so this is the only record that reaches further back.
    private static let historyFile = AppDir.url.appendingPathComponent("runs.jsonl")

    public func save() { write(to: Self.file) }

    public func saveAsLastRun() {
        write(to: Self.lastRunFile)
        appendToHistory()
    }

    private func appendToHistory() {
        guard var line = try? JSONEncoder().encode(self) else { return }
        line.append(0x0A)
        guard let handle = try? FileHandle(forWritingTo: Self.historyFile) else {
            try? line.write(to: Self.historyFile)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private func write(to url: URL) {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url, options: .atomic) }
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
