import Foundation
import UserNotifications
import LidlezzCore

/// macOS banners. Silently does nothing when run outside an .app bundle.
final class Notifier {
    private var center: UNUserNotificationCenter? { Bundle.main.bundleIdentifier == nil ? nil : .current() }
    /// One banner per kind of notice at a time, and the same text at most once per ten minutes.
    private var lastPosted: [String: (body: String, at: Date)] = [:]
    private let repeatInterval: TimeInterval = 600

    func requestPermission(_ done: @escaping (Bool) -> Void) {
        guard let center else { done(false); return }
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in DispatchQueue.main.async { done(ok) } }
    }

    func isAllowed(_ done: @escaping (Bool) -> Void) {
        guard let center else { done(false); return }
        center.getNotificationSettings { s in DispatchQueue.main.async { done(s.authorizationStatus == .authorized) } }
    }

    func post(_ notice: Notice) {
        let (title, body): (String, String)
        switch notice {
        case .modeOn:
            (title, body) = ("Lid-closed mode on", "Claude Code will run in the background when you close the lid.")
        case .warm(let t):
            (title, body) = ("Running warm · \(Int(t))°", "Throttling further. Consider taking the Mac out of the bag.")
        case .batteryLow(let p):
            (title, body) = ("Battery at \(p)%", "Lid-closed mode turns off at \(Settings.batteryFloor)%.")
        case .finished(let why):
            (title, body) = ("Task finished", why)
        case .emergency(let why):
            (title, body) = ("Lidlezz turned lid-closed mode off", why)
        case .limitWait:
            (title, body) = ("Usage limit reached", "Keeping the Mac awake so Claude Code can continue when the limit resets.")
        case .trialOver:
            (title, body) = ("Trial over", "Buy a license to keep using lid-closed mode.")
        }
        let kind = String(describing: notice).prefix { $0 != "(" }.description
        if let last = lastPosted[kind], last.body == body, Date().timeIntervalSince(last.at) < repeatInterval { return }
        lastPosted[kind] = (body, Date())
        guard let center else { print("[notice] \(title): \(body)"); return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: kind, content: content, trigger: nil))
    }
}
