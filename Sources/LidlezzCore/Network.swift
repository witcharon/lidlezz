import Foundation
import Network

/// Wi-Fi, for the case where the Mac loses every network mid-run: rejoin a network macOS already
/// knows (an iPhone hotspot) so Claude Code does not stop and the run does not end in a sleep.
public enum WiFi {
    /// The Wi-Fi interface, usually "en0".
    public static let device: String? = {
        let lines = networksetup(["-listallhardwareports"]).components(separatedBy: .newlines)
        guard let i = lines.firstIndex(where: { $0.hasPrefix("Hardware Port: Wi-Fi") }), i + 1 < lines.count,
              let name = lines[i + 1].split(separator: ":").last else { return nil }
        return name.trimmingCharacters(in: .whitespaces)
    }()

    /// Networks macOS already has the password for. The hotspot has to be joined by hand once.
    public static func saved() -> [String] {
        guard let device else { return [] }
        return networksetup(["-listpreferredwirelessnetworks", device])
            .components(separatedBy: .newlines).dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Joins `ssid` off the caller's thread: associating can block for half a minute.
    /// Wi-Fi that the user switched off stays off; this is for being out of range, not for
    /// overriding a deliberate choice.
    /// The phone hotspots among them. macOS does not mark a saved network as a hotspot and the
    /// live scan hides names unless the app asks for Location, so this goes by name. Falls back to
    /// every saved network when nothing looks like a phone, so the setting is never a dead end.
    public static func savedHotspots() -> [String] {
        let hints = ["iphone", "ipad", "hotspot", "erişim noktası", "erisim noktasi",
                     "android", "galaxy", "samsung", "xiaomi", "redmi", "huawei"]
        let all = saved()
        let phones = all.filter { name in
            let lower = name.lowercased()
            return hints.contains { lower.contains($0) }
        }
        return phones.isEmpty ? all : phones
    }

    public static func join(_ ssid: String) {
        guard let device, !joining else { return }
        joining = true
        DispatchQueue.global().async {
            _ = networksetup(["-setairportnetwork", device, ssid])
            joining = false
        }
    }

    private static var joining = false

    private static func networksetup(_ args: [String]) -> String {
        Shell.run("/usr/sbin/networksetup", args).output
    }
}

/// Whether the Mac has a network at all. A watcher, not a poll, so a tick costs nothing.
public final class Connectivity {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var satisfied = true

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock(); satisfied = path.status == .satisfied; lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "lidlezz.network"))
    }

    public var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }
        return satisfied
    }
}
