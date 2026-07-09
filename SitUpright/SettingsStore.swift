import Foundation
import CoreMotion
import ServiceManagement
import Combine

/// Persists all user settings and the calibration baseline in `UserDefaults`.
/// This type owns NO CoreMotion or UI logic — it is a plain observable store so
/// the SwiftUI popover can bind to it and stay in sync with disk.
final class SettingsStore: ObservableObject {

    private enum Key {
        static let sensitivity        = "sensitivity"
        static let warningThreshold   = "warningThreshold"
        static let badThreshold       = "badThreshold"
        static let alertDelay         = "alertDelay"
        static let notificationsOn    = "notificationsEnabled"
        static let soundOn            = "soundEnabled"
        static let launchAtLogin      = "launchAtLogin"
        static let hasCalibration     = "hasCalibration"
        static let baselineW          = "baselineW"
        static let baselineX          = "baselineX"
        static let baselineY          = "baselineY"
        static let baselineZ          = "baselineZ"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Published, persisted settings

    /// 0 = very forgiving (thresholds scaled up), 1 = very sensitive (thresholds scaled down).
    @Published var sensitivity: Double {
        didSet { defaults.set(sensitivity, forKey: Key.sensitivity) }
    }

    /// Base warning angle in degrees before sensitivity scaling. Default 10°.
    @Published var warningThreshold: Double {
        didSet { defaults.set(warningThreshold, forKey: Key.warningThreshold) }
    }

    /// Base "bad posture" angle in degrees before sensitivity scaling. Default 18°.
    @Published var badThreshold: Double {
        didSet { defaults.set(badThreshold, forKey: Key.badThreshold) }
    }

    /// Seconds of sustained poor posture before an alert fires. Default 8s.
    @Published var alertDelay: Double {
        didSet { defaults.set(alertDelay, forKey: Key.alertDelay) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsOn) }
    }

    /// Plays a short ping when poor posture is sustained past the alert delay.
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundOn) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    // MARK: - Calibration baseline (stored as a unit quaternion)

    @Published private(set) var hasCalibration: Bool

    /// The neutral head orientation captured during calibration, or nil if never calibrated.
    private(set) var baselineQuaternion: CMQuaternion?

    // MARK: - Fixed tuning constants

    /// Exponential-smoothing factor. Small = smoother/slower, large = twitchier.
    let smoothingAlpha: Double = 0.18

    // MARK: - Init

    init() {
        // Register sensible defaults so first launch is well-behaved.
        defaults.register(defaults: [
            Key.sensitivity: 0.5,
            Key.warningThreshold: 10.0,
            Key.badThreshold: 18.0,
            Key.alertDelay: 10.0,
            Key.notificationsOn: true,
            Key.soundOn: true,
            Key.launchAtLogin: false,
            Key.hasCalibration: false
        ])

        sensitivity          = defaults.double(forKey: Key.sensitivity)
        warningThreshold     = defaults.double(forKey: Key.warningThreshold)
        badThreshold         = defaults.double(forKey: Key.badThreshold)
        alertDelay           = defaults.double(forKey: Key.alertDelay)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsOn)
        soundEnabled         = defaults.bool(forKey: Key.soundOn)
        launchAtLogin        = defaults.bool(forKey: Key.launchAtLogin)
        hasCalibration       = defaults.bool(forKey: Key.hasCalibration)

        if hasCalibration {
            baselineQuaternion = CMQuaternion(
                x: defaults.double(forKey: Key.baselineX),
                y: defaults.double(forKey: Key.baselineY),
                z: defaults.double(forKey: Key.baselineZ),
                w: defaults.double(forKey: Key.baselineW)
            )
        }
    }

    // MARK: - Effective (sensitivity-scaled) thresholds used by the detector

    /// At sensitivity 0.5 the scale is 1.0; higher sensitivity lowers the trigger angle.
    private var scale: Double { 1.5 - sensitivity }        // 1.5 ... 0.5
    var effectiveWarning: Double { warningThreshold * scale }
    var effectiveBad: Double { badThreshold * scale }

    // MARK: - Baseline persistence

    func setBaseline(_ q: CMQuaternion) {
        baselineQuaternion = q
        hasCalibration = true
        defaults.set(true, forKey: Key.hasCalibration)
        defaults.set(q.w, forKey: Key.baselineW)
        defaults.set(q.x, forKey: Key.baselineX)
        defaults.set(q.y, forKey: Key.baselineY)
        defaults.set(q.z, forKey: Key.baselineZ)
    }

    func clearBaseline() {
        baselineQuaternion = nil
        hasCalibration = false
        defaults.set(false, forKey: Key.hasCalibration)
    }

    // MARK: - Launch at login (macOS 13+ ServiceManagement)

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("SitUpright: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
