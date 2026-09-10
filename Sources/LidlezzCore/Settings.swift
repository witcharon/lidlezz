import Foundation

/// The one user setting plus onboarding state.
public enum Settings {
    /// One domain for the app and the CLI.
    private static let defaults = UserDefaults(suiteName: HelperIdentity.appBundleID + ".settings")!

    /// Lid-closed mode turns itself off when the battery reaches this percentage.
    public static var batteryFloor: Int {
        get { defaults.object(forKey: "batteryFloor") as? Int ?? 15 }
        set { defaults.set(newValue, forKey: "batteryFloor") }
    }

    public static var autoStart: Bool {
        get { defaults.object(forKey: "autoStart") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoStart") }
    }

    /// Minutes without Claude Code activity before an automatically started mode turns off.
    public static var idleMinutes: Int {
        get { defaults.object(forKey: "idleMinutes") as? Int ?? 10 }
        set { defaults.set(newValue, forKey: "idleMinutes") }
    }

    /// Last list fetched from the site. Kept across launches so a revoked key stays revoked offline.
    public static var revokedIDs: [String] {
        get { defaults.stringArray(forKey: "revokedIDs") ?? [] }
        set { defaults.set(newValue, forKey: "revokedIDs") }
    }

    public static var licenseKey: String? {
        get { defaults.string(forKey: "licenseKey") }
        set { defaults.set(newValue, forKey: "licenseKey") }
    }

    /// Start of the trial. Recorded the first time anything reads it.
    public static var firstLaunch: Date {
        if let d = defaults.object(forKey: "firstLaunch") as? Date { return d }
        let now = Date()
        defaults.set(now, forKey: "firstLaunch")
        return now
    }

    public static var onboarded: Bool {
        get { defaults.bool(forKey: "onboarded") }
        set { defaults.set(newValue, forKey: "onboarded") }
    }
}
