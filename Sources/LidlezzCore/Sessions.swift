import Foundation

/// One agent session as reported by that tool's hooks. Stored as a JSON file per session;
/// the file's freshness is the lease, so a crashed session expires on its own.
public struct Session: Codable, Identifiable {
    public let id: String
    /// Which tool reported this. Absent in files written before Lidlezz knew more than one agent.
    public var agent: String?
    public var cwd: String
    public var prompt: String
    public var toolCalls: Int
    public var working: Bool
    /// Claude Code hit a usage limit and is waiting for the reset to continue by itself.
    public var waiting: Bool
    public var updatedAt: Date

    /// Anything that still needs the Mac awake.
    public var busy: Bool { working || waiting }

    public var shortID: String { String(id.suffix(6)) }
    public var project: String { (cwd as NSString).abbreviatingWithTildeInPath }
    public var agentName: String { Agents.agent(agent ?? "claude")?.name ?? "Agent" }
    /// Never empty: agents that report no working directory still need a name in the list.
    public var label: String { project.isEmpty ? agentName : project }
}

public enum Sessions {
    public static let leaseSeconds: TimeInterval = 3600
    /// Usage limits reset up to five hours later.
    public static let waitingLeaseSeconds: TimeInterval = 6 * 3600
    private static let dir = AppDir.url.appendingPathComponent("sessions", isDirectory: true)

    private static func file(_ id: String) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    /// Applies one hook payload. `event` is what the agent's own wiring passed on the command line;
    /// Claude Code names the event inside the payload instead, so it may be empty.
    public static func apply(agent: String, event: String, payload data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        switch agent {
        case "claude": applyClaude(json)
        case "cursor": applyCursor(event: event, json)
        case "antigravity": applyAntigravity(event: event, json)
        case "opencode": applyOpencode(event: event, json)
        case "codex": applyCodex(json)
        default: break
        }
    }

    // MARK: agent adapters

    private static func applyClaude(_ json: [String: Any]) {
        guard let raw = json["session_id"] as? String,
              let event = json["hook_event_name"] as? String else { return }
        let id = "claude:" + raw
        if event == "SessionEnd" { end(id); return }
        update(id, agent: "claude", cwd: json["cwd"] as? String) { s in
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
                default: break
                }
            default: break
            }
        }
    }

    private static func applyCursor(event: String, _ json: [String: Any]) {
        let raw = (json["conversation_id"] as? String) ?? (json["session_id"] as? String) ?? "session"
        let id = "cursor:" + raw
        let name = (json["hook_event_name"] as? String) ?? event
        if name == "sessionEnd" { end(id); return }
        let cwd = (json["cwd"] as? String) ?? (json["workspace_roots"] as? [String])?.first
        update(id, agent: "cursor", cwd: cwd) { s in
            switch name {
            case "beforeSubmitPrompt":
                s.prompt = String(((json["prompt"] as? String) ?? "").prefix(80))
                s.toolCalls = 0
                s.working = true
            case "preToolUse": s.toolCalls += 1; s.working = true
            case "stop": s.working = false
            default: break
            }
        }
    }

    private static func applyAntigravity(event: String, _ json: [String: Any]) {
        let raw = (json["conversationId"] as? String) ?? "session"
        let cwd = (json["workspacePaths"] as? [String])?.first
        update("antigravity:" + raw, agent: "antigravity", cwd: cwd) { s in
            switch event {
            case "PreToolUse": s.toolCalls += 1; s.working = true
            case "Stop": s.working = false
            default: break
            }
        }
    }

    private static func applyOpencode(event: String, _ json: [String: Any]) {
        // opencode gives the plugin a project directory but no session id, so the project is the session.
        let cwd = (json["cwd"] as? String) ?? "opencode"
        update("opencode:" + cwd, agent: "opencode", cwd: cwd) { s in
            switch event {
            case "tool.execute.before": s.toolCalls += 1; s.working = true
            case "session.idle": s.working = false
            default: break
            }
        }
    }

    /// Codex only reports the end of a turn. Its sessions are created from the running process
    /// (see `observe`), and this marks them done.
    private static func applyCodex(_ json: [String: Any]) {
        // The turn that ended is the one in that directory; each session keeps its own.
        let cwd = json["cwd"] as? String
        for s in all() where s.agent == "codex" && (cwd == nil || s.cwd.isEmpty || s.cwd == cwd) {
            update(s.id, agent: "codex", cwd: nil) { $0.working = false }
        }
    }

    /// Agents whose hooks cannot say when a turn begins get one session per running process, and the
    /// process itself supplies the missing signal: while a turn runs the agent spawns child processes
    /// for the tools it calls, and at its prompt it has none. The end of a turn still comes from the
    /// hook, which is the half Codex does report.
    public static func observe(processes: [ProcessEntry]) {
        for agent in Agents.all where agent.startsUnknown {
            let live = processes.filter { agent.processNames.contains($0.name) }
            for p in live {
                let runningTools = processes.contains { $0.ppid == p.pid }
                update("\(agent.id):\(p.pid)", agent: agent.id, cwd: Processes.workingDirectory(of: p.pid)) { s in
                    if runningTools { s.working = true }
                }
            }
            // The process is the session. Once it is gone — finished, killed, crashed mid-turn —
            // so is its claim on the Mac; without this a dead agent would hold sleep off for the
            // rest of the lease.
            let alive = Set(live.map { "\(agent.id):\($0.pid)" })
            for s in all() where s.agent == agent.id && !alive.contains(s.id) { end(s.id) }
        }
    }

    // MARK: storage

    private static func update(_ id: String, agent: String, cwd: String?, _ change: (inout Session) -> Void) {
        var s = load(id) ?? Session(id: id, agent: agent, cwd: "", prompt: "", toolCalls: 0,
                                    working: false, waiting: false, updatedAt: Date())
        s.agent = agent
        if let cwd, !cwd.isEmpty { s.cwd = cwd }
        change(&s)
        s.updatedAt = Date()
        // Atomic: the app reads these files while the hooks write them.
        if let out = try? JSONEncoder().encode(s) { try? out.write(to: file(id), options: .atomic) }
    }

    private static func end(_ id: String) { try? FileManager.default.removeItem(at: file(id)) }

    private static func load(_ id: String) -> Session? {
        guard let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static func all() -> [Session] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Session.self, from: data)
        }
    }

    /// Sessions whose lease has not expired. Expired files are removed.
    public static func active() -> [Session] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let s = try? JSONDecoder().decode(Session.self, from: data) else { return nil }
            // Files from before sessions were namespaced by agent; drop them rather than double-count.
            if !s.id.contains(":") { try? FileManager.default.removeItem(at: url); return nil }
            if Date().timeIntervalSince(s.updatedAt) > (s.waiting ? waitingLeaseSeconds : leaseSeconds) {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return s
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
