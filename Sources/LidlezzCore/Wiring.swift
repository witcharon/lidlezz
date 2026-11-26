import Foundation

/// One writer per agent, because every tool spells "run this on each event" differently.
/// All of them only ever touch entries carrying our own command, so a user's own hooks survive.

// MARK: - Claude Code — ~/.claude/settings.json

enum ClaudeWiring {
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Stop", "StopFailure",
                         "Notification", "SessionEnd"]
    private static let arguments = "hook claude"
    private static let signature = " " + arguments
    private static var file: URL { Agents.home.appendingPathComponent(".claude/settings.json") }

    private static func isOurs(_ group: Any) -> Bool {
        guard let g = group as? [String: Any], let inner = g["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(signature) == true }
    }

    static func isInstalled() -> Bool {
        guard let hooks = JSONFile.read(file)?["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { (hooks[$0] as? [Any])?.contains(where: isOurs) == true }
    }

    static func install(_ executable: String) -> Bool {
        guard var json = JSONFile.read(file) else { return false }
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        let group: [String: Any] = ["hooks": [["type": "command", "command": Agents.hookCommand(executable, arguments)]]]
        for event in events {
            var groups = ((hooks[event] as? [Any]) ?? []).filter { !isOurs($0) }
            groups.append(group)
            hooks[event] = groups
        }
        json["hooks"] = hooks
        return JSONFile.write(json, to: file)
    }

    static func uninstall() -> Bool {
        guard var json = JSONFile.read(file) else { return false }
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
        guard let hooks = JSONFile.read(file)?["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { (hooks[$0] as? [Any])?.contains(where: isOurs) == true }
    }

    static func install(_ executable: String) -> Bool {
        guard var json = JSONFile.read(file) else { return false }
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
        guard var json = JSONFile.read(file) else { return false }
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
        guard let ours = JSONFile.read(file)?[group] as? [String: Any] else { return false }
        return events.allSatisfy { ours[$0] != nil }
    }

    static func install(_ executable: String) -> Bool {
        guard var json = JSONFile.read(file) else { return false }
        var ours: [String: Any] = [:]
        for event in events {
            let handler = ["type": "command", "command": Agents.hookCommand(executable, "hook antigravity \(event)")]
            // Tool events take a matcher around their handlers; the others list the handlers directly.
            ours[event] = event == "PreToolUse" ? [["matcher": ".*", "hooks": [handler]]] : [handler]
        }
        json[group] = ours
        return JSONFile.write(json, to: file)
    }

    static func uninstall() -> Bool {
        guard var json = JSONFile.read(file) else { return false }
        guard json.removeValue(forKey: group) != nil else { return true }
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

// MARK: - Hermes Agent — a hooks: block in ~/.hermes/config.yaml

/// Hermes takes shell hooks from its YAML config and only runs the ones listed in its allowlist.
/// The desktop app and the gateway never ask, so connecting Lidlezz writes both.
enum HermesWiring {
    /// A turn starts at pre_llm_call and on_session_end closes every turn, finished or interrupted.
    static let events = ["pre_llm_call", "pre_tool_call", "on_session_end"]
    private static let signature = " hook hermes"
    private static let begin = "# >>> lidlezz"
    private static let end = "# <<< lidlezz"
    private static var file: URL { Agents.home.appendingPathComponent(".hermes/config.yaml") }
    private static var allowlist: URL { Agents.home.appendingPathComponent(".hermes/shell-hooks-allowlist.json") }

    private static func lines() -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").components(separatedBy: "\n")
    }

    /// The lines between our markers, markers included.
    private static func block(_ lines: [String]) -> ClosedRange<Int>? {
        guard let first = lines.firstIndex(of: begin),
              let last = lines[first...].firstIndex(of: end) else { return nil }
        return first...last
    }

    static func isInstalled() -> Bool {
        lines().filter { $0.contains(signature) }.count >= events.count
    }

    static func install(_ executable: String) -> Bool {
        var rest = lines()
        if let ours = block(rest) { rest.removeSubrange(ours) }
        // YAML allows one hooks: key, and merging into someone else's by hand would risk their file.
        guard !rest.contains(where: { $0.hasPrefix("hooks:") }) else { return false }
        let command = "\"\(executable)\"\(signature)"
        let scalar = "'" + command.replacingOccurrences(of: "'", with: "''") + "'"
        while rest.last?.isEmpty == true { rest.removeLast() }
        rest.append(begin)
        rest.append("hooks:")
        for event in events { rest += ["  \(event):", "    - command: \(scalar)", "      timeout: 10"] }
        rest += [end, ""]
        guard write(rest) else { return false }
        return approve { approvals in approvals + events.map { ["event": $0, "command": command] } }
    }

    static func uninstall() -> Bool {
        var rest = lines()
        guard let ours = block(rest) else { return !isInstalled() }
        rest.removeSubrange(ours)
        guard write(rest) else { return false }
        return !FileManager.default.fileExists(atPath: allowlist.path) || approve { $0 }
    }

    /// Rewrites the allowlist without our entries, then with whatever `change` adds.
    private static func approve(_ change: ([Any]) -> [Any]) -> Bool {
        guard var json = JSONFile.read(allowlist) else { return false }
        let others = ((json["approvals"] as? [Any]) ?? []).filter {
            (($0 as? [String: Any])?["command"] as? String)?.contains(signature) != true
        }
        json["approvals"] = change(others)
        return JSONFile.write(json, to: allowlist)
    }

    private static func write(_ lines: [String]) -> Bool {
        (try? lines.joined(separator: "\n").write(to: file.resolvingSymlinksInPath(), atomically: true, encoding: .utf8)) != nil
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

    /// The `notify = [...]` assignment: the lines it covers (the array may span several) and its argv.
    private static func notifyEntry(_ lines: [String]) -> (range: Range<Int>, argv: [String])? {
        guard let start = lines.firstIndex(where: { $0.range(of: #"^\s*notify\s*="#, options: .regularExpression) != nil })
        else { return nil }
        let opensArray = lines[start].range(of: #"=\s*\["#, options: .regularExpression) != nil
        let end = opensArray ? lines[start...].firstIndex { $0.contains("]") } ?? start : start
        return (start..<end + 1, strings(in: lines[start...end].joined(separator: "\n")))
    }

    /// Every TOML string in `text`: "basic" ones read like JSON, 'literal' ones are taken as they are.
    private static func strings(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|'[^']*'"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let token = String(text[Range(match.range, in: text)!])
            if token.hasPrefix("'") { return String(token.dropFirst().dropLast()) }
            return try? JSONSerialization.jsonObject(with: Data(token.utf8), options: .fragmentsAllowed) as? String
        }
    }

    /// An argv as a TOML array, which for plain strings is the same text as JSON.
    private static func array(_ argv: [String]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: argv, options: [.withoutEscapingSlashes])) ?? Data("[]".utf8),
               as: UTF8.self)
    }

    private static func isOurs(_ argv: [String]) -> Bool {
        let command = argv.joined(separator: " ")
        return command.contains(signature) || command.contains("hook codex")
    }

    static func isInstalled() -> Bool {
        notifyEntry(lines()).map { isOurs($0.argv) } ?? false
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
        var rest = lines()
        let entry = notifyEntry(rest)
        let previous = entry.map { isOurs($0.argv) ? savedPrevious() : $0.argv } ?? []

        var command = "\"\(executable)\" hook codex \"$1\" >/dev/null 2>&1 || true"
        if !previous.isEmpty {
            command += "\nexec " + previous.map(Shell.quoted).joined(separator: " ") + " \"$@\""
        }
        let source = """
        #!/bin/sh
        # Lidlezz. Tells Lidlezz a Codex turn finished, then runs the notify command that was here before.
        \(previousMarker)\(array(previous))
        \(command)
        """
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? source.write(to: script, atomically: true, encoding: .utf8)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        if let entry { rest.removeSubrange(entry.range) }
        // A bare key has to sit above the first [section] in TOML.
        rest.insert("notify = \(array([script.path]))", at: 0)
        return write(rest)
    }

    static func uninstall() -> Bool {
        var rest = lines()
        // Someone else's notify command is not ours to remove.
        guard let entry = notifyEntry(rest), isOurs(entry.argv) else { return true }
        // Put back whatever notify command Lidlezz displaced.
        let previous = savedPrevious()
        try? FileManager.default.removeItem(at: script)
        rest.removeSubrange(entry.range)
        if !previous.isEmpty { rest.insert("notify = \(array(previous))", at: entry.range.lowerBound) }
        return write(rest)
    }

    private static func write(_ lines: [String]) -> Bool {
        (try? lines.joined(separator: "\n").write(to: file.resolvingSymlinksInPath(), atomically: true, encoding: .utf8)) != nil
    }
}
