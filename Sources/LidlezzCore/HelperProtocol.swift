import Foundation
import Security

/// What the root helper does for the app. Only these three switches, nothing general-purpose.
@objc public protocol LidlezzHelperProtocol {
    func setSleepDisabled(_ on: Bool, reply: @escaping (Bool) -> Void)
    func setLowPowerMode(_ on: Bool, reply: @escaping (Bool) -> Void)
    func setTimeMachine(enabled: Bool, reply: @escaping (Bool) -> Void)
    func ping(reply: @escaping (String) -> Void)
}

public enum HelperIdentity {
    public static let appBundleID = "com.cansincengiz.lidlezz"
    public static let machService = "com.cansincengiz.lidlezz.helper"
    public static let plistName = "com.cansincengiz.lidlezz.helper.plist"
    public static let version = "1"
    /// Only the Lidlezz app (or its bundled CLI) signed by the same team as the helper may talk to it,
    /// so anyone building from source with their own certificate gets a working helper.
    /// An unsigned or ad hoc helper has no team, and then the requirement matches nothing.
    public static var clientRequirement: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(ownTeamID ?? "-")\" and (identifier \"\(appBundleID)\" or identifier \"lidlezz\")"
    }

    /// The team that signed the running binary.
    static var ownTeamID: String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
