import Foundation

public struct ProcessEntry: Identifiable, Hashable {
    public let pid: Int32
    public let ppid: Int32
    public let name: String
    public let args: String
    public var id: Int32 { pid }
}

/// Agent processes and their children; background QoS; pausing heavy daemons.
public enum Processes {
    private static func snapshot() -> [ProcessEntry] {
        Shell.run("/bin/ps", ["-axo", "pid=,ppid=,args="]).output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { return nil }
                let args = String(parts[2])
                let exe = args.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
                let name = exe.split(separator: "/").last.map(String.init) ?? exe
                let rest = args.dropFirst(exe.count).trimmingCharacters(in: .whitespaces)
                return ProcessEntry(pid: pid, ppid: ppid, name: name, args: rest)
            }
    }

    /// Every known agent process followed by its descendants.
    public static func agentTree() -> [ProcessEntry] {
        let all = snapshot()
        var children: [Int32: [ProcessEntry]] = [:]
        for e in all { children[e.ppid, default: []].append(e) }
        var seen = Set<Int32>()
        var result: [ProcessEntry] = []
        let names = Agents.throttleNames
        var queue = all.filter { names.contains($0.name) }
        while !queue.isEmpty {
            let e = queue.removeFirst()
            guard seen.insert(e.pid).inserted else { continue }
            result.append(e)
            queue.append(contentsOf: children[e.pid] ?? [])
        }
        return result
    }

    public static func setBackground(_ pids: Set<Int32>, _ on: Bool) {
        for pid in pids { Shell.run("/usr/sbin/taskpolicy", [on ? "-b" : "-B", "-p", String(pid)]) }
    }

    /// User-level daemons that burn CPU for nothing while the lid is closed.
    public static let pausable: [(label: String, process: String)] = [
        ("Photos analysis", "photoanalysisd"),
        ("Media analysis", "mediaanalysisd"),
    ]

    public static func setPaused(_ paused: Bool) -> [String] {
        let all = snapshot()
        return pausable.compactMap { item in
            let pids = all.filter { $0.name == item.process }.map(\.pid)
            guard !pids.isEmpty else { return nil }
            for pid in pids { kill(pid, paused ? SIGSTOP : SIGCONT) }
            return item.label
        }
    }
}
