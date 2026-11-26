import Foundation

/// The coding agents Lidlezz knows about.
///
/// Two things are wanted from each: which processes to throttle when the lid closes, and — where the
/// tool offers a hook API — when it is actually working, so the Mac only stays awake for real work.
/// A tool without hooks still gets throttling, temperature and battery protection; it just has to be
/// switched on by hand.
public struct Agent: Identifiable, Hashable {
    public let id: String
    public let name: String
    /// Processes belonging to this agent. Matched by exact name, so "claude" and "Claude" differ.
    public let processNames: [String]
    /// A desktop app that sits open all day. Its presence says nothing about whether work is happening.
    public let longLived: Bool
    let wiring: Wiring
    /// Present on this Mac at all.
    let marker: [String]

    public var canReportActivity: Bool { wiring != .none }
    /// Codex only reports the end of a turn, never the start, so its sessions come from the process list.
    public var startsUnknown: Bool { wiring == .codexNotify }

    enum Wiring: Equatable {
        case claudeSettings, cursorHooks, antigravityHooks, opencodePlugin, codexNotify, hermesHooks, none
    }
}

public enum Agents {
    /// LIDLEZZ_HOME lets a test run point every config path at a scratch directory.
    static var home: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["LIDLEZZ_HOME"] ?? NSHomeDirectory())
    }

    public static let all: [Agent] = [
        Agent(id: "claude", name: "Claude Code", processNames: ["claude"], longLived: false,
              wiring: .claudeSettings, marker: ["~/.claude", "/usr/local/bin/claude", "~/.local/bin/claude"]),
        Agent(id: "codex", name: "Codex CLI", processNames: ["codex"], longLived: false,
              wiring: .codexNotify, marker: ["~/.codex", "/usr/local/bin/codex", "~/.local/bin/codex"]),
        Agent(id: "opencode", name: "opencode", processNames: ["opencode"], longLived: false,
              wiring: .opencodePlugin, marker: ["~/.config/opencode", "/usr/local/bin/opencode", "~/.opencode"]),
        Agent(id: "cursor", name: "Cursor", processNames: ["Cursor", "Cursor Helper", "Cursor Helper (Renderer)",
                                                           "Cursor Helper (Plugin)", "cursor-agent"],
              longLived: true, wiring: .cursorHooks, marker: ["~/.cursor", "/Applications/Cursor.app"]),
        Agent(id: "antigravity", name: "Antigravity", processNames: ["Antigravity", "Antigravity Helper",
                                                                     "Antigravity Helper (Renderer)", "antigravity"],
              longLived: true, wiring: .antigravityHooks, marker: ["~/.gemini", "/Applications/Antigravity.app"]),
        Agent(id: "hermes", name: "Hermes Agent", processNames: ["Hermes", "Hermes Helper",
                                                                  "Hermes Helper (Renderer)", "hermes"],
              longLived: true, wiring: .hermesHooks, marker: ["~/.hermes"]),
        Agent(id: "claude-app", name: "Claude for Mac", processNames: ["Claude", "Claude Helper",
                                                                       "Claude Helper (Renderer)"],
              longLived: true, wiring: .none, marker: ["/Applications/Claude.app"]),
    ]

    public static func agent(_ id: String) -> Agent? { all.first { $0.id == id } }

    /// Agents actually installed on this Mac. The setup window only offers these.
    public static func present() -> [Agent] {
        all.filter { agent in agent.marker.contains { FileManager.default.fileExists(atPath: expand($0)) } }
    }

    /// Every process name worth throttling while the lid is closed.
    public static var throttleNames: Set<String> { Set(all.flatMap(\.processNames)) }

    /// Names of agents that exit when their work is done, so their absence means nothing is running.
    public static var shortLivedNames: Set<String> { Set(all.filter { !$0.longLived }.flatMap(\.processNames)) }

    /// A hook command for agents that run it through a shell. Once Lidlezz is removed it does
    /// nothing, instead of failing on every event the agent reports.
    static func hookCommand(_ executable: String, _ arguments: String) -> String {
        "[ -x \"\(executable)\" ] && \"\(executable)\" \(arguments) || true"
    }

    static func expand(_ path: String) -> String {
        path.hasPrefix("~") ? home.path + String(path.dropFirst(1)) : path
    }

    // MARK: wiring

    public static func isWired(_ agent: Agent) -> Bool {
        switch agent.wiring {
        case .claudeSettings: return ClaudeWiring.isInstalled()
        case .cursorHooks: return CursorWiring.isInstalled()
        case .antigravityHooks: return AntigravityWiring.isInstalled()
        case .opencodePlugin: return OpencodeWiring.isInstalled()
        case .codexNotify: return CodexWiring.isInstalled()
        case .hermesHooks: return HermesWiring.isInstalled()
        case .none: return false
        }
    }

    @discardableResult
    public static func wire(_ agent: Agent, executable: String) -> Bool {
        switch agent.wiring {
        case .claudeSettings: return ClaudeWiring.install(executable)
        case .cursorHooks: return CursorWiring.install(executable)
        case .antigravityHooks: return AntigravityWiring.install(executable)
        case .opencodePlugin: return OpencodeWiring.install(executable)
        case .codexNotify: return CodexWiring.install(executable)
        case .hermesHooks: return HermesWiring.install(executable)
        case .none: return false
        }
    }

    @discardableResult
    public static func unwire(_ agent: Agent) -> Bool {
        switch agent.wiring {
        case .claudeSettings: return ClaudeWiring.uninstall()
        case .cursorHooks: return CursorWiring.uninstall()
        case .antigravityHooks: return AntigravityWiring.uninstall()
        case .opencodePlugin: return OpencodeWiring.uninstall()
        case .codexNotify: return CodexWiring.uninstall()
        case .hermesHooks: return HermesWiring.uninstall()
        case .none: return true
        }
    }
}

// MARK: - shared JSON file helpers

enum JSONFile {
    /// Empty when there is no file yet. Nil when the file is there but is not a JSON object:
    /// writing our hooks over it would throw away everything the user had in it.
    static func read(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Atomic, so the agent never reads half a file; through symlinks, so a dotfiles link stays a link.
    static func write(_ json: [String: Any], to url: URL) -> Bool {
        let target = url.resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return false }
        return (try? data.write(to: target, options: .atomic)) != nil
    }
}
