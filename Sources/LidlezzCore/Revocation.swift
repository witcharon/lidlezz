import Foundation

/// Refunded or leaked keys. The site publishes opaque license ids; no email ever appears in it.
/// Every failure path keeps the last known list, so a customer offline — or a dead server —
/// never loses a license they paid for.
public enum Revocation {
    public static func refresh(_ done: (() -> Void)? = nil) {
        var request = URLRequest(url: Site.revoked)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ids = json["revoked"] as? [String]
            else { return }
            Settings.revokedIDs = ids
            DispatchQueue.main.async { done?() }
        }.resume()
    }
}
