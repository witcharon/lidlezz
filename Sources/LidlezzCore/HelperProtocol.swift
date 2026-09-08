import Foundation

/// What the root helper does for the app. Only these three switches, nothing general-purpose.
@objc public protocol LidlezzHelperProtocol {
    func setSleepDisabled(_ on: Bool, reply: @escaping (Bool) -> Void)
    func setLowPowerMode(_ on: Bool, reply: @escaping (Bool) -> Void)
    func setTimeMachine(enabled: Bool, reply: @escaping (Bool) -> Void)
    func ping(reply: @escaping (String) -> Void)
}

public enum HelperIdentity {
    public static let appBundleID = "com.cansincengiz.lidlezz"
    public static let teamID = "TB4RR5PW57"
    public static let machService = "com.cansincengiz.lidlezz.helper"
    public static let plistName = "com.cansincengiz.lidlezz.helper.plist"
    public static let version = "1"
    /// Only the signed Lidlezz app (or its bundled CLI) may talk to the helper.
    public static let clientRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and (identifier \"\(appBundleID)\" or identifier \"lidlezz\")"
}
