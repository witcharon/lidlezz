import Foundation

/// One Claude Code session as reported by its hooks. Stored as a JSON file per session;
/// the file's freshness is the lease, so a crashed session expires on its own.
public struct Session: Codable, Identifiable {
    public let id: String
    public var cwd: String
    public var prompt: String
    public var toolCalls: Int
    public var working: Bool
    /// Claude Code hit a usage limit and is waiting for the reset to continue by itself.
    public var waiting: Bool
    public var updatedAt: Date

    /// Anything that still needs the Mac awake.
    public var busy: Bool { working || waiting }

    public var shortID: String { String(id.prefix(6)) }
    public var project: String { (cwd as NSString).abbreviatingWithTildeInPath }
}

public enum Sessions {
    public static let leaseSeconds: TimeInterval = 3600
    /// Usage limits reset up to five hours later.
    public static let waitingLeaseSeconds: TimeInterval = 6 * 3600
    private static let dir = AppDir.url.appendingPathComponent("sessions", isDirectory: true)

    private static func file(_ id: String) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(id + ".json")
    }

    /// Applies one Claude Code hook payload (the JSON Claude Code pipes to stdin).
    public static func apply(hookPayload data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["session_id"] as? String,
              let event = json["hook_event_name"] as? String
        else { return }
        if event == "SessionEnd" { try? FileManager.default.removeItem(at: file(id)); return }

        var s = load(id) ?? Session(id: id, cwd: "", prompt: "", toolCalls: 0, working: false, waiting: false, updatedAt: Date())
        if let cwd = json["cwd"] as? String { s.cwd = cwd }
        switch event {
        case "UserPromptSubmit":
            s.prompt = String(((json["prompt"] as? String) ?? "").prefix(80))
            s.toolCalls = 0
            s.working = true; s.waiting = false
        case "PreToolUse": s.toolCalls += 1; s.working = true; s.waiting = false
        case "Stop": s.working = false; s.waiting = false
        case "StopFailure":
            s.working = false
            s.waiting = (json["error"] as? String) == "rate_limit"
        case "Notification":
            switch json["notification_type"] as? String {
            case "quota_auto_resume_fired": s.working = true; s.waiting = false
            case "quota_auto_resume_stale", "quota_auto_resume_disabled": s.waiting = false
            default: return
            }
        default: break
        }
        s.updatedAt = Date()
        if let out = try? JSONEncoder().encode(s) { try? out.write(to: file(id)) }
    }

    private static func load(_ id: String) -> Session? {
        guard let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    /// Sessions whose lease has not expired. Expired files are removed.
    public static func active() -> [Session] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let s = try? JSONDecoder().decode(Session.self, from: data) else { return nil }
            if Date().timeIntervalSince(s.updatedAt) > (s.waiting ? waitingLeaseSeconds : leaseSeconds) {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return s
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
