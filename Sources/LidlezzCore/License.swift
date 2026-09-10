import CryptoKit
import Foundation

/// Offline license check: `LZ-<base64url payload>.<base64url Ed25519 signature>`, signed by the site.
/// The signature is the whole check; the network is only ever consulted to learn that a key was revoked.
public struct License {
    /// Public half of the key pair made with scripts/keygen.mjs. The site signs with the private half.
    public static let publicKeyBase64 = "yaALSPfG1KogRHyxwhtFAj42Go0Ui0AWd8QdzMMJpNc="
    public static let trialDays = 7

    public let email: String
    public let issuedAt: Date
    /// Opaque per-purchase id. The published revocation list names these, never emails.
    public let id: String?

    public static func parse(_ raw: String) -> License? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("LZ-") else { return nil }
        let parts = key.dropFirst(3).split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let payload = Data(base64URL: parts[0]), let signature = Data(base64URL: parts[1]),
              let keyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              publicKey.isValidSignature(signature, for: payload),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let email = json["e"] as? String, let issued = json["t"] as? Double
        else { return nil }
        return License(email: email, issuedAt: Date(timeIntervalSince1970: issued), id: json["i"] as? String)
    }

    // MARK: current state

    public enum Status {
        case licensed(License)
        case trial(daysLeft: Int)
        case expired
        case revoked
    }

    public static var status: Status {
        if let key = Settings.licenseKey, let license = parse(key) {
            if let id = license.id, Settings.revokedIDs.contains(id) { return .revoked }
            return .licensed(license)
        }
        let start = Settings.firstLaunch
        let elapsedDays = Int(max(0, Date().timeIntervalSince(start)) / 86400)
        let left = trialDays - elapsedDays
        return left > 0 ? .trial(daysLeft: left) : .expired
    }

    public static var isActive: Bool {
        switch status {
        case .licensed, .trial: return true
        case .expired, .revoked: return false
        }
    }
}

extension Data {
    init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
