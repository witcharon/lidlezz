import Foundation

/// The one user setting plus onboarding state.
public enum Settings {
    /// One domain for the app and the CLI.
    private static let defaults = UserDefaults(suiteName: HelperIdentity.appBundleID + ".settings")!

    /// Lid-closed mode turns itself off when the battery reaches this percentage.
    public static let batteryFloorRange = 5...50

    public static var batteryFloor: Int {
        get { min(defaults.object(forKey: "batteryFloor") as? Int ?? 15, batteryFloorRange.upperBound) }
        set { defaults.set(newValue, forKey: "batteryFloor") }
    }

    public static var autoStart: Bool {
        get { defaults.object(forKey: "autoStart") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoStart") }
    }

    /// Start with the user's session: after a restart nothing else brings Lidlezz back, and
    /// agents that carry on working would be left unguarded.
    public static var openAtLogin: Bool {
        get { defaults.object(forKey: "openAtLogin") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "openAtLogin") }
    }

    /// Minutes without Claude Code activity before an automatically started mode turns off.
    public static var idleMinutes: Int {
        get { defaults.object(forKey: "idleMinutes") as? Int ?? 10 }
        set { defaults.set(newValue, forKey: "idleMinutes") }
    }

    /// Wi-Fi network to rejoin when the Mac goes offline mid-run. Empty means never.
    public static var rejoinSSID: String {
        get { defaults.string(forKey: "rejoinSSID") ?? "" }
        set { defaults.set(newValue, forKey: "rejoinSSID") }
    }

    public static var onboarded: Bool {
        get { defaults.bool(forKey: "onboarded") }
        set { defaults.set(newValue, forKey: "onboarded") }
    }
}
