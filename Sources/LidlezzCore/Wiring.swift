import Foundation

/// One writer per agent, because every tool spells "run this on each event" differently.
/// All of them only ever touch entries carrying our own command, so a user's own hooks survive.

// MARK: - Claude Code — ~/.claude/settings.json

enum ClaudeWiring {
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Stop", "StopFailure",
                         "Notification", "SessionEnd"]
    private static let signature = " hook claude"
    private static var file: URL { Agents.home.appendingPathComponent(".claude/settings.json") }

    private static func isOurs(_ group: Any) -> Bool {
        guard let g = group as? [String: Any], let inner = g["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(signature) == true }
    }

    static func isInstalled() -> Bool {
        guard let hooks = JSONFile.read(file)["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { (hooks[$0] as? [Any])?.contains(where: isOurs) == true }
    }

    static func install(_ executable: String) -> Bool {
        var json = JSONFile.read(file)
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        let group: [String: Any] = ["hooks": [["type": "command", "command": "\"\(executable)\"\(signature)"]]]
        for event in events {
            var groups = ((hooks[event] as? [Any]) ?? []).filter { !isOurs($0) }
            groups.append(group)
            hooks[event] = groups
        }
        json["hooks"] = hooks
        return JSONFile.write(json, to: file)
    }

    static func uninstall() -> Bool {
        var json = JSONFile.read(file)
        guard var hooks = json["hooks"] as? [String: Any] else { return true }
        for event in events {
            let rest = ((hooks[event] as? [Any]) ?? []).filter { !isOurs($0) }
            if rest.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = rest }
        }
        json["hooks"] = hooks
        return JSONFile.write(json, to: file)
    }
}

// MARK: - Cursor — ~/.cursor/hooks.json

enum CursorWiring {
    /// Cursor names the event in every payload, but the command carries it too so one parser fits all agents.
    static let events = ["sessionStart", "beforeSubmitPrompt", "preToolUse", "stop", "sessionEnd"]
    private static let signature = " hook cursor"
    private static var file: URL { Agents.home.appendingPathComponent(".cursor/hooks.json") }

    private static func isOurs(_ entry: Any) -> Bool {
        ((entry as? [String: Any])?["command"] as? String)?.contains(signature) == true
    }

    static func isInstalled() -> Bool {
        guard let hooks = JSONFile.read(file)["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { (hooks[$0] as? [Any])?.contains(where: isOurs) == true }
    }

    static func install(_ executable: String) -> Bool {
        var json = JSONFile.read(file)
        json["version"] = 1
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        for event in events {
            var entries = ((hooks[event] as? [Any]) ?? []).filter { !isOurs($0) }
            entries.append(["command": "\"\(executable)\"\(signature) \(event)"])
            hooks[event] = entries
        }
        json["hooks"] = hooks
        return JSONFile.write(json, to: file)
    }

    static func uninstall() -> Bool {
        var json = JSONFile.read(file)
        guard var hooks = json["hooks"] as? [String: Any] else { return true }
        for event in events {
            let rest = ((hooks[event] as? [Any]) ?? []).filter { !isOurs($0) }
            if rest.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = rest }
        }
        json["hooks"] = hooks
        return JSONFile.write(json, to: file)
    }
}

// MARK: - Antigravity — ~/.gemini/config/hooks.json

enum AntigravityWiring {
    /// Antigravity's payload does not name the event, so the command has to.
    static let events = ["PreToolUse", "Stop"]
    private static let group = "lidlezz"
    private static var file: URL { Agents.home.appendingPathComponent(".gemini/config/hooks.json") }

    static func isInstalled() -> Bool {
        guard let ours = JSONFile.read(file)[group] as? [String: Any] else { return false }
        return events.allSatisfy { ours[$0] != nil }
    }

    static func install(_ executable: String) -> Bool {
        var json = JSONFile.read(file)
        var ours: [String: Any] = [:]
        for event in events {
            ours[event] = [["hooks": [["type": "command",
                                       "command": "\"\(executable)\" hook antigravity \(event)"]]]]
        }
        json[group] = ours
        return JSONFile.write(json, to: file)
    }

    static func uninstall() -> Bool {
        var json = JSONFile.read(file)
        json.removeValue(forKey: group)
        return JSONFile.write(json, to: file)
    }
}

// MARK: - opencode — a plugin file

enum OpencodeWiring {
    /// The docs disagree on the folder name, so write both; opencode loads whichever it reads.
    private static var files: [URL] {
        ["plugin", "plugins"].map {
            Agents.home.appendingPathComponent(".config/opencode/\($0)/lidlezz.js")
        }
    }

    static func isInstalled() -> Bool {
        files.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func install(_ executable: String) -> Bool {
        let source = """
        // Lidlezz. Reports opencode activity so the Mac only stays awake while the agent works.
        // Written by Lidlezz; delete this file to disconnect it.
        import { execFile } from "node:child_process";

        const report = (event, data) =>
          new Promise((done) =>
            execFile("\(executable)", ["hook", "opencode", event, JSON.stringify(data)], () => done()),
          );

        export const Lidlezz = async ({ directory }) => ({
          event: async ({ event }) => {
            if (event?.type === "session.idle") await report("session.idle", { cwd: directory });
          },
          "tool.execute.before": async (input) =>
            await report("tool.execute.before", { cwd: directory, tool: input?.tool ?? "" }),
        });
        """
        var wrote = false
        for url in files {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if (try? source.write(to: url, atomically: true, encoding: .utf8)) != nil { wrote = true }
        }
        return wrote
    }

    static func uninstall() -> Bool {
        for url in files { try? FileManager.default.removeItem(at: url) }
        return true
    }
}

// MARK: - Codex — the notify key in ~/.codex/config.toml

/// Codex allows exactly one notify command. If the user already has one, Lidlezz does not take it
/// away: it installs a small script that reports the turn and then runs whatever was there before.
enum CodexWiring {
    private static let signature = "lidlezz-notify.sh"
    private static let previousMarker = "# lidlezz-previous: "
    private static var file: URL { Agents.home.appendingPathComponent(".codex/config.toml") }
    private static var script: URL { Agents.home.appendingPathComponent(".codex/lidlezz-notify.sh") }

    private static func lines() -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").components(separatedBy: .newlines)
    }

    private static func notifyLine(_ lines: [String]) -> String? {
        lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }
    }

    /// The argv array on the right of `notify =`, which is also valid JSON.
    private static func tokens(_ line: String) -> [String] {
        guard let eq = line.firstIndex(of: "="),
              let data = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return array
    }

    static func isInstalled() -> Bool {
        notifyLine(lines())?.contains(signature) == true || notifyLine(lines())?.contains("hook codex") == true
    }

    private static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// What the user had before Lidlezz, remembered inside the script so re-running install
    /// never loses it.
    private static func savedPrevious() -> [String] {
        guard let text = try? String(contentsOf: script, encoding: .utf8),
              let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix(previousMarker) }),
              let data = String(line.dropFirst(previousMarker.count)).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return array
    }

    static func install(_ executable: String) -> Bool {
        let existing = notifyLine(lines())
        let ours = (existing?.contains(signature) ?? false) || (existing?.contains("hook codex") ?? false)
        let previous = ours ? savedPrevious() : (existing.map(tokens) ?? [])
        let keepPrevious = !previous.isEmpty

        var command = "\"\(executable)\" hook codex \"$1\" >/dev/null 2>&1 || true"
        if keepPrevious {
            command += "\nexec " + previous.map(shellQuoted).joined(separator: " ") + " \"$@\""
        }
        let source = """
        #!/bin/sh
        # Lidlezz. Tells Lidlezz a Codex turn finished, then runs the notify command that was here before.
        \(previousMarker)\(String(data: (try? JSONSerialization.data(withJSONObject: keepPrevious ? previous : [],
                                            options: [.withoutEscapingSlashes])) ?? Data(), encoding: .utf8) ?? "[]")
        \(command)
        """
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? source.write(to: script, atomically: true, encoding: .utf8)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        var rest = lines().filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }
        // A bare key has to sit above the first [section] in TOML.
        rest.insert("notify = [\"\(script.path)\"]", at: 0)
        return (try? rest.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)) != nil
    }

    static func uninstall() -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return true }
        // Put back whatever notify command Lidlezz displaced.
        let saved = ((try? String(contentsOf: script, encoding: .utf8)) ?? "")
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix(previousMarker) }
            .map { String($0.dropFirst(previousMarker.count)) } ?? "[]"
        try? FileManager.default.removeItem(at: script)

        var rest = lines().filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }
        if saved != "[]", !saved.isEmpty { rest.insert("notify = \(saved)", at: 0) }
        return (try? rest.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)) != nil
    }
}
