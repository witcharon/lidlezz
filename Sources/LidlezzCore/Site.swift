import Foundation

/// Every outward-facing URL in one place. Change the domain here when it is final.
public enum Site {
    public static let base = URL(string: "https://lidlezz.app")!
    public static let latest = base.appendingPathComponent("latest.json")
    /// Not appendingPathComponent: that escapes the fragment into /%23donate.
    public static let donate = URL(string: "https://lidlezz.app/#donate")!
}
