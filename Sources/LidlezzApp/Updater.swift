import Foundation
import LidlezzCore
import Sparkle

/// Two paths, because the right way to update depends on how the app was installed.
///
/// Downloaded the DMG: Sparkle checks, downloads, installs and relaunches.
/// Installed with Homebrew: brew owns the app, so Lidlezz only says a version is out and
/// offers the command; running the update itself would desync Homebrew's record.
final class Updater: NSObject, ObservableObject {
    /// Set for Homebrew installs only; the panel shows it and offers to copy the command.
    @Published private(set) var available: (version: String, url: URL)?

    private var sparkle: SPUStandardUpdaterController?
    private var notifiedVersion: String?
    private let notifier: Notifier

    init(notifier: Notifier) {
        self.notifier = notifier
        super.init()
        if !Install.isHomebrew {
            sparkle = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
    }

    var canSelfUpdate: Bool { sparkle != nil }

    /// Menu action for DMG installs: Sparkle's own "checking…" and "update available" windows.
    func checkNow() { sparkle?.checkForUpdates(nil) }

    /// Background check. Sparkle runs its own schedule, so this only covers the Homebrew path.
    func check() {
        guard sparkle == nil else { return }
        URLSession.shared.dataTask(with: Site.latest) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let version = json["version"], let url = json["url"].flatMap(URL.init(string:)),
                  let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  version.compare(current, options: .numeric) == .orderedDescending
            else { return }
            DispatchQueue.main.async {
                self.available = (version, url)
                guard self.notifiedVersion != version else { return }
                self.notifiedVersion = version
                self.notifier.post(.updateAvailable(version))
            }
        }.resume()
    }
}
