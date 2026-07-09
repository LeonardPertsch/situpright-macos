import SwiftUI
import CoreMotion

/// Compact popover UI. Binds directly to the observable stores so it updates live
/// as motion samples arrive. Deliberately minimal and text-forward — no emoji,
/// no decorative styling.
struct PosturePopoverView: View {

    @ObservedObject var settings: SettingsStore
    @ObservedObject var service: HeadphoneMotionService
    @ObservedObject var detector: PostureDetector

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusBlock
            Divider()
            controls
            Divider()
            preferences
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("SitUpright")
                .font(.headline)
            Spacer()
            Text(service.isConnected ? "AirPods connected" : "No AirPods")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status

    private var statusBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                Text(availabilityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.0f°", detector.deviationDegrees))
                    .font(.title2.monospacedDigit())
                Text("deviation")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Primary controls

    private var controls: some View {
        VStack(spacing: 8) {
            Button(service.isTracking ? "Stop Tracking" : "Start Tracking") {
                if service.isTracking {
                    service.stop()
                    detector.reset()
                } else {
                    service.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            Button("Calibrate Upright Posture") {
                detector.calibrate()
            }
            .frame(maxWidth: .infinity)
            .disabled(!(service.isTracking && service.status == .active))

            if service.isTracking && !detector.isCalibrated {
                Text("Sit upright, then calibrate to set your baseline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Preferences

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    Text(sensitivityLabel).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                Slider(value: $settings.sensitivity, in: 0...1)
            }

            HStack {
                Text("Alert delay")
                Spacer()
                Text("\(Int(settings.alertDelay)) s").foregroundStyle(.secondary)
                Stepper("", value: $settings.alertDelay, in: 3...30, step: 1)
                    .labelsHidden()
            }
            .font(.subheadline)

            Toggle("Notifications", isOn: $settings.notificationsEnabled)
                .font(.subheadline)

            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .font(.subheadline)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(String(format: "Warn %.0f° · Bad %.0f°",
                        settings.effectiveWarning, settings.effectiveBad))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
    }

    // MARK: - Derived display values

    private var sensitivityLabel: String {
        switch settings.sensitivity {
        case ..<0.34: return "Low"
        case ..<0.67: return "Medium"
        default:      return "High"
        }
    }

    private var statusColor: Color {
        guard service.isTracking, service.status == .active else { return .secondary }
        guard detector.isCalibrated else { return .yellow }
        switch detector.state {
        case .good:        return .primary
        case .borderline:  return .yellow
        case .poor:        return .red
        case .unavailable: return .secondary
        }
    }

    private var statusText: String {
        switch service.status {
        case .unsupported:  return "Headphone motion unavailable"
        case .unauthorized: return "Motion access denied"
        case .disconnected: return "AirPods not connected"
        case .error:        return "Motion error"
        case .idle:         return "Ready to track"
        case .active:
            guard detector.isCalibrated else { return "Calibrate to begin" }
            switch detector.state {
            case .good:        return "Good posture"
            case .borderline:  return "Leaning forward"
            case .poor:        return "Slouching"
            case .unavailable: return "Tracking"
            }
        }
    }

    private var availabilityText: String {
        switch service.status {
        case .unauthorized:
            return "Enable in System Settings › Privacy › Motion & Fitness"
        case .disconnected, .unsupported:
            return "Connect AirPods Pro/3rd gen, AirPods Max, or compatible Beats"
        case .error(let message):
            return message
        default:
            return service.isTracking ? "Tracking active" : "Tracking stopped"
        }
    }
}
