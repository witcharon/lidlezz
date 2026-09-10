import Foundation

/// Every outward-facing URL in one place. Change the domain here when it is final.
public enum Site {
    public static let base = URL(string: "https://lidlezz.app")!
    public static let latest = base.appendingPathComponent("latest.json")
    public static let revoked = base.appendingPathComponent("revoked.json")
    /// Not appendingPathComponent: that escapes the fragment into /%23buy.
    public static let buy = URL(string: "https://lidlezz.app/#buy")!
}
