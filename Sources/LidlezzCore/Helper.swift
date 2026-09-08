import Foundation
import ServiceManagement

/// Client side of the root helper: registration through SMAppService and synchronous XPC calls.
public enum Helper {
    private static let service = SMAppService.daemon(plistName: HelperIdentity.plistName)

    public enum State {
        case ready, needsApproval, notInstalled, installedButUnreachable
    }

    public static func state() -> State {
        switch service.status {
        case .enabled: return isReachable() ? .ready : .installedButUnreachable
        case .requiresApproval: return .needsApproval
        default: return .notInstalled
        }
    }

    /// Registers the daemon. macOS then asks the user to allow it under Login Items › Allow in the Background.
    public static func install() -> State {
        try? service.register()
        let s = state()
        if s == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
        return s
    }

    public static func uninstall() { try? service.unregister() }

    public static func isReachable() -> Bool {
        var version = ""
        _ = call(timeout: 2) { proxy, done in proxy.ping { version = $0; done(true) } }
        return version == HelperIdentity.version
    }

    public static func setSleepDisabled(_ on: Bool) -> Bool { call { $0.setSleepDisabled(on, reply: $1) } }
    public static func setLowPowerMode(_ on: Bool) -> Bool { call { $0.setLowPowerMode(on, reply: $1) } }
    public static func setTimeMachine(enabled: Bool) -> Bool { call { $0.setTimeMachine(enabled: enabled, reply: $1) } }

    private static func call(timeout: TimeInterval = 5,
                             _ body: (LidlezzHelperProtocol, @escaping (Bool) -> Void) -> Void) -> Bool {
        let connection = NSXPCConnection(machServiceName: HelperIdentity.machService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: LidlezzHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let done = DispatchSemaphore(value: 0)
        var ok = false
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in done.signal() }) as? LidlezzHelperProtocol
        else { return false }
        body(proxy) { ok = $0; done.signal() }
        _ = done.wait(timeout: .now() + timeout)
        return ok
    }
}
