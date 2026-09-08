import Foundation
import LidlezzCore

/// Checks the site's latest.json on launch and every six hours. No auto-install: the panel shows a link.
final class Updater {
    private(set) var available: (version: String, url: URL)?

    func check(_ done: @escaping () -> Void) {
        URLSession.shared.dataTask(with: Site.latest) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let version = json["version"], let url = json["url"].flatMap(URL.init(string:)),
                  let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  version.compare(current, options: .numeric) == .orderedDescending
            else { return }
            DispatchQueue.main.async { self?.available = (version, url); done() }
        }.resume()
    }
}
