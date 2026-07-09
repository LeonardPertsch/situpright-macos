import Foundation
import CoreMotion
import Combine

/// Pure posture math. Consumes attitude quaternions, produces a smoothed deviation
/// angle and a discrete posture state, and decides when a "sustained slouch" alert
/// should fire. Contains NO CoreMotion acquisition and NO UI.
final class PostureDetector: ObservableObject {

    enum PostureState { case unavailable, good, borderline, poor }

    @Published private(set) var state: PostureState = .unavailable
    @Published private(set) var deviationDegrees: Double = 0
    @Published private(set) var isCalibrated: Bool

    private let settings: SettingsStore
    private let notifications: NotificationService

    // Smoothing / detection state
    private var smoothed: Double = 0
    private var hasSample = false
    private var poorSince: TimeInterval?      // motion-clock time poor posture began
    private var lastNotified: TimeInterval = -.greatestFiniteMagnitude

    // Latest raw sample, kept so calibration can snapshot the current orientation.
    private var latestQuaternion: CMQuaternion?

    init(settings: SettingsStore, notifications: NotificationService) {
        self.settings = settings
        self.notifications = notifications
        self.isCalibrated = settings.hasCalibration
    }

    /// Called when tracking stops so the menu bar returns to a neutral state.
    func reset() {
        state = .unavailable
        deviationDegrees = 0
        smoothed = 0
        hasSample = false
        poorSince = nil
    }

    // MARK: - Calibration

    /// >>> CALIBRATION <<<
    /// Snapshots the current head orientation as the upright baseline. All future
    /// deviations are measured relative to this, so the app never judges absolute
    /// head orientation — only how far you've moved from *your* neutral.
    @discardableResult
    func calibrate() -> Bool {
        guard let q = latestQuaternion else { return false }
        settings.setBaseline(q)
        isCalibrated = true
        smoothed = 0
        hasSample = false
        poorSince = nil
        return true
    }

    // MARK: - Per-sample processing

    func process(quaternion q: CMQuaternion, timestamp t: TimeInterval) {
        latestQuaternion = q

        guard let baseline = settings.baselineQuaternion else {
            // Not calibrated yet: report zero deviation and don't judge posture.
            deviationDegrees = 0
            state = .good
            return
        }

        // >>> DEVIATION MATH <<<
        // Relative rotation from baseline to current = inverse(baseline) * current.
        // Working in the relative frame makes the measurement independent of how the
        // user was facing when they calibrated.
        let relative = quatMultiply(quatInverse(baseline), q)

        // Forward head posture is a nod (pitch) about the head's X axis. We extract
        // just that component so turning the head left/right (yaw) does not trigger.
        let pitchRadians = pitch(from: relative)
        let degrees = abs(pitchRadians * 180.0 / .pi)

        // >>> SMOOTHING <<<
        // Exponential moving average removes sensor jitter and ignores brief glances,
        // so we only react to sustained posture rather than momentary movement.
        let alpha = settings.smoothingAlpha
        if hasSample {
            smoothed = alpha * degrees + (1 - alpha) * smoothed
        } else {
            smoothed = degrees
            hasSample = true
        }
        deviationDegrees = smoothed

        updateState(now: t)
    }

    // MARK: - Threshold + sustained-alert logic

    private func updateState(now: TimeInterval) {
        // >>> THRESHOLD DETECTION <<<
        let warn = settings.effectiveWarning
        let bad  = settings.effectiveBad

        let newState: PostureState
        if smoothed >= bad {
            newState = .poor
        } else if smoothed >= warn {
            newState = .borderline
        } else {
            newState = .good
        }
        state = newState

        if newState == .poor {
            // Require the poor state to persist for `alertDelay` seconds before alerting.
            if poorSince == nil { poorSince = now }
            if let since = poorSince, now - since >= settings.alertDelay {
                maybeNotify(now: now)
            }
        } else {
            poorSince = nil
        }
    }

    private func maybeNotify(now: TimeInterval) {
        guard settings.notificationsEnabled else { return }
        // Cooldown prevents notification spam while the user stays slouched.
        guard now - lastNotified >= settings.notificationCooldown else { return }
        lastNotified = now
        notifications.sendPostureAlert(deviationDegrees: deviationDegrees)
    }
}

// MARK: - Quaternion helpers (unit quaternions only)

/// Inverse of a unit quaternion is its conjugate.
private func quatInverse(_ q: CMQuaternion) -> CMQuaternion {
    CMQuaternion(x: -q.x, y: -q.y, z: -q.z, w: q.w)
}

/// Hamilton product a * b.
private func quatMultiply(_ a: CMQuaternion, _ b: CMQuaternion) -> CMQuaternion {
    CMQuaternion(
        x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    )
}

/// Rotation about the X (pitch / nod) axis extracted from a quaternion, in radians.
private func pitch(from q: CMQuaternion) -> Double {
    let sinp = 2.0 * (q.w * q.x + q.y * q.z)
    let cosp = 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
    return atan2(sinp, cosp)
}
