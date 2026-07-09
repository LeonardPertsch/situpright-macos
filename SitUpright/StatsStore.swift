import Foundation
import Combine

/// Immutable summary the UI renders.
struct StatsSnapshot: Equatable {
    var totalSeconds: Double = 0
    var goodSeconds: Double = 0
    var borderlineSeconds: Double = 0
    var poorSeconds: Double = 0
    /// Time-weighted average deviation from the calibrated optimum, in degrees.
    var averageDeviation: Double = 0
}

/// Accumulates all-time posture statistics: how long tracking ran and how far from the
/// calibrated optimum you were. Persisted in `UserDefaults` so totals survive relaunches.
/// Kept separate from CoreMotion acquisition and from the posture math.
final class StatsStore: ObservableObject {

    private enum Key {
        static let total      = "stats.totalSeconds"
        static let good       = "stats.goodSeconds"
        static let borderline = "stats.borderlineSeconds"
        static let poor       = "stats.poorSeconds"
        static let integral   = "stats.deviationIntegral"
    }

    private let defaults = UserDefaults.standard

    // Raw accumulators (seconds, and deviation·seconds for the integral).
    private var totalSeconds: Double
    private var goodSeconds: Double
    private var borderlineSeconds: Double
    private var poorSeconds: Double
    private var deviationIntegral: Double

    private var lastTimestamp: TimeInterval?
    private var lastPublishedTotal: Double = 0
    private var lastSavedTotal: Double = 0

    /// Throttled, published view of the accumulators.
    @Published private(set) var snapshot: StatsSnapshot

    init() {
        totalSeconds      = defaults.double(forKey: Key.total)
        goodSeconds       = defaults.double(forKey: Key.good)
        borderlineSeconds = defaults.double(forKey: Key.borderline)
        poorSeconds       = defaults.double(forKey: Key.poor)
        deviationIntegral = defaults.double(forKey: Key.integral)
        snapshot          = StatsSnapshot()
        lastPublishedTotal = totalSeconds
        lastSavedTotal = totalSeconds
        snapshot = makeSnapshot()
    }

    // MARK: - Accumulation

    /// Called once per motion sample. Integrates the elapsed time (dt) into the totals,
    /// weighting the deviation by dt so the average is time-correct regardless of sample
    /// rate. Large gaps (tracking paused / headphones removed) are ignored.
    func record(state: PostureDetector.PostureState,
                deviation: Double,
                timestamp t: TimeInterval,
                calibrated: Bool) {
        defer { lastTimestamp = t }
        guard calibrated, let last = lastTimestamp else { return }

        let dt = t - last
        guard dt > 0, dt < 2 else { return }   // skip pauses / clock jumps

        totalSeconds += dt
        deviationIntegral += deviation * dt
        switch state {
        case .good:        goodSeconds += dt
        case .borderline:  borderlineSeconds += dt
        case .poor:        poorSeconds += dt
        case .unavailable: break
        }

        // Throttle UI updates (~1s) and disk writes (~10s) to avoid per-sample churn.
        if totalSeconds - lastPublishedTotal >= 1.0 {
            lastPublishedTotal = totalSeconds
            snapshot = makeSnapshot()
        }
        if totalSeconds - lastSavedTotal >= 10.0 {
            lastSavedTotal = totalSeconds
            save()
        }
    }

    /// Call when tracking stops so the final slice is shown and saved, and the next
    /// session doesn't integrate the idle gap.
    func flush() {
        lastTimestamp = nil
        snapshot = makeSnapshot()
        save()
    }

    func reset() {
        totalSeconds = 0; goodSeconds = 0; borderlineSeconds = 0; poorSeconds = 0
        deviationIntegral = 0
        lastTimestamp = nil
        lastPublishedTotal = 0
        lastSavedTotal = 0
        snapshot = makeSnapshot()
        save()
    }

    // MARK: - Helpers

    private func makeSnapshot() -> StatsSnapshot {
        StatsSnapshot(
            totalSeconds: totalSeconds,
            goodSeconds: goodSeconds,
            borderlineSeconds: borderlineSeconds,
            poorSeconds: poorSeconds,
            averageDeviation: totalSeconds > 0 ? deviationIntegral / totalSeconds : 0
        )
    }

    private func save() {
        defaults.set(totalSeconds, forKey: Key.total)
        defaults.set(goodSeconds, forKey: Key.good)
        defaults.set(borderlineSeconds, forKey: Key.borderline)
        defaults.set(poorSeconds, forKey: Key.poor)
        defaults.set(deviationIntegral, forKey: Key.integral)
    }
}
