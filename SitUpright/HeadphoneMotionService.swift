import Foundation
import CoreMotion
import Combine

/// Thin wrapper around `CMHeadphoneMotionManager`.
///
/// Responsibility: acquire raw motion data from AirPods/compatible headphones and
/// publish availability/connection/authorization state. It performs NO posture math —
/// it only forwards the attitude quaternion (a value type) to `onMotion`.
final class HeadphoneMotionService: NSObject, ObservableObject {

    enum TrackingStatus: Equatable {
        case idle           // supported + authorized (or undetermined) + connected, not running
        case unsupported    // device motion never available on this Mac/headphones
        case unauthorized   // user denied Motion & Fitness access
        case disconnected   // no motion-capable headphones connected
        case active         // updates flowing
        case error(String)  // runtime error from CoreMotion
    }

    @Published private(set) var status: TrackingStatus = .idle
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isTracking: Bool = false

    /// Called on the main thread for every motion sample while tracking.
    /// Passes only Sendable value types (quaternion + timestamp) — never the manager.
    var onMotion: ((CMQuaternion, TimeInterval) -> Void)?

    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.example.SitUpright.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    override init() {
        super.init()
        manager.delegate = self
        refreshStatus()
    }

    var authorizationStatus: CMAuthorizationStatus {
        CMHeadphoneMotionManager.authorizationStatus()
    }

    /// Recomputes the idle status from current authorization + hardware availability.
    func refreshStatus() {
        isConnected = manager.isDeviceMotionAvailable
        if !isTracking {
            status = idleStatus()
        }
    }

    private func idleStatus() -> TrackingStatus {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            return .unauthorized
        default:
            break
        }
        // isDeviceMotionAvailable is false both when headphones are absent and when the
        // connected headphones have no motion sensors. We surface it as "disconnected".
        return manager.isDeviceMotionAvailable ? .idle : .disconnected
    }

    // MARK: - Start / stop

    func start() {
        guard !isTracking else { return }

        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            status = .unauthorized
            return
        default:
            break
        }

        guard manager.isDeviceMotionAvailable else {
            status = .disconnected
            return
        }

        // Starting updates is also what triggers the first-time permission prompt.
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async { self.status = .error(error.localizedDescription) }
                return
            }
            guard let motion else { return }

            // >>> MOTION DATA ACQUISITION <<<
            // Extract the attitude as a quaternion (device-neutral, no gimbal wrap issues)
            // plus the monotonic timestamp, then hand off on the main thread.
            let q = motion.attitude.quaternion
            let t = motion.timestamp
            DispatchQueue.main.async {
                self.isTracking = true
                self.status = .active
                self.onMotion?(q, t)
            }
        }

        isTracking = true
        status = .active
    }

    func stop() {
        guard isTracking else { return }
        manager.stopDeviceMotionUpdates()
        isTracking = false
        status = idleStatus()
    }
}

// MARK: - Connect / disconnect notifications

extension HeadphoneMotionService: CMHeadphoneMotionManagerDelegate {

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            self.isConnected = true
            if !self.isTracking { self.status = self.idleStatus() }
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.status = .disconnected
        }
    }
}
