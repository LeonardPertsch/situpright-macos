import AppKit

/// Wires the components together and keeps the app running as a menu-bar-only
/// accessory. Owns the long-lived services.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = SettingsStore()
    private lazy var notifications = NotificationService()
    private let service = HeadphoneMotionService()
    private lazy var detector = PostureDetector(settings: settings, notifications: notifications)
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: even without LSUIElement this keeps us out of the Dock.
        NSApp.setActivationPolicy(.accessory)

        notifications.requestAuthorizationIfNeeded()

        // Route raw motion (from CoreMotion) into the posture math. This is the only
        // seam between data acquisition and detection.
        service.onMotion = { [weak self] quaternion, timestamp in
            self?.detector.process(quaternion: quaternion, timestamp: timestamp)
        }

        menuBar = MenuBarController(settings: settings, service: service, detector: detector)
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
    }
}
