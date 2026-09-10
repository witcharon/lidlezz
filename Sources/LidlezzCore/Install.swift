import Foundation

/// How this copy of Lidlezz was installed. Homebrew keeps its own record of the app, so a
/// brew-installed copy must be upgraded with brew; a self-update would leave the two disagreeing.
public enum Install {
    public static var isHomebrew: Bool {
        ["/opt/homebrew/Caskroom/lidlezz", "/usr/local/Caskroom/lidlezz"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    public static let brewUpgradeCommand = "brew upgrade --cask lidlezz"
}
