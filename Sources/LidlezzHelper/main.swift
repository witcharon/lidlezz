import Foundation
import LidlezzCore

/// Root daemon. Runs pmset/tmutil for the signed Lidlezz app and nothing else.
final class Service: NSObject, LidlezzHelperProtocol {
    private func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func setSleepDisabled(_ on: Bool, reply: @escaping (Bool) -> Void) {
        reply(run("/usr/bin/pmset", ["-a", "disablesleep", on ? "1" : "0"]))
    }

    func setLowPowerMode(_ on: Bool, reply: @escaping (Bool) -> Void) {
        reply(run("/usr/bin/pmset", ["-a", "lowpowermode", on ? "1" : "0"]))
    }

    func setTimeMachine(enabled: Bool, reply: @escaping (Bool) -> Void) {
        reply(run("/usr/bin/tmutil", [enabled ? "enable" : "disable"]))
    }

    func ping(reply: @escaping (String) -> Void) { reply(HelperIdentity.version) }
}

final class Listener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(HelperIdentity.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: LidlezzHelperProtocol.self)
        connection.exportedObject = Service()
        connection.resume()
        return true
    }
}

// The sudoers rule from early builds is no longer needed.
try? FileManager.default.removeItem(atPath: "/etc/sudoers.d/lidlezz")

let delegate = Listener()
let listener = NSXPCListener(machServiceName: HelperIdentity.machService)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
