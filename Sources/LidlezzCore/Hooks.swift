import Foundation

/// Installs `lidlezz hook claude` into ~/.claude/settings.json so Claude Code reports
/// session activity. Only groups carrying our signature are ever touched.
public enum Hooks {
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Stop", "StopFailure", "Notification", "SessionEnd"]
    private static let signature = " hook claude"
    private static let settings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    private static func read() -> [String: Any] {
        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private static func write(_ json: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return false }
        return (try? data.write(to: settings)) != nil
    }

    private static func isOurs(_ group: Any) -> Bool {
        guard let g = group as? [String: Any], let inner = g["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(signature) == true }
    }

    public static func isInstalled() -> Bool {
        guard let hooks = read()["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { (hooks[$0] as? [Any])?.contains(where: isOurs) == true }
    }

    public static func install(executable: String) -> Bool {
        var json = read()
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        let group: [String: Any] = ["hooks": [["type": "command", "command": "\"\(executable)\"\(signature)"]]]
        for event in events {
            var groups = ((hooks[event] as? [Any]) ?? []).filter { !isOurs($0) }
            groups.append(group)
            hooks[event] = groups
        }
        json["hooks"] = hooks
        return write(json)
    }

    public static func uninstall() -> Bool {
        var json = read()
        guard var hooks = json["hooks"] as? [String: Any] else { return true }
        for event in events {
            let rest = ((hooks[event] as? [Any]) ?? []).filter { !isOurs($0) }
            if rest.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = rest }
        }
        json["hooks"] = hooks
        return write(json)
    }
}
