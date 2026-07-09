import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter`. Requests permission lazily and posts posture
/// reminders. Cooldown/sustain logic lives in `PostureDetector`; this type only
/// delivers a notification when asked.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Ask once at launch. Safe to call repeatedly; the system remembers the choice.
    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("SitUpright: notification auth error: \(error.localizedDescription)")
            } else {
                NSLog("SitUpright: notification permission granted = \(granted)")
            }
        }
    }

    func sendPostureAlert(deviationDegrees: Double) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Sit upright"
            content.body = String(
                format: "You've been leaning forward (%.0f°). Reset your posture.",
                deviationDegrees
            )
            content.sound = .default   // subtle, system-supported

            // Immediate delivery (trigger nil). Unique id so alerts don't collapse.
            let request = UNNotificationRequest(
                identifier: "posture-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            self.center.add(request) { error in
                if let error {
                    NSLog("SitUpright: failed to post notification: \(error.localizedDescription)")
                }
            }
        }
    }

    // Show banners even while the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
