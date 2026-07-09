import SwiftUI
import CoreMotion

/// Compact popover UI. Binds directly to the observable stores so it updates live
/// as motion samples arrive. Deliberately minimal and text-forward — no emoji,
/// no decorative styling.
struct PosturePopoverView: View {

    @ObservedObject var settings: SettingsStore
    @ObservedObject var service: HeadphoneMotionService
    @ObservedObject var detector: PostureDetector
    @ObservedObject var stats: StatsStore
    let sound: SoundService

    init(settings: SettingsStore,
         service: HeadphoneMotionService,
         detector: PostureDetector,
         sound: SoundService,
         stats: StatsStore) {
        self.settings = settings
        self.service = service
        self.detector = detector
        self.sound = sound
        self.stats = stats
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusBlock
                Divider()
                controls
                Divider()
                statistics
                Divider()
                preferences
                Divider()
                footer
            }
            .padding(16)
            .frame(width: 300)
        }
        .frame(width: 300, height: 600)
    }

    // MARK: - Statistics

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Statistics")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 16) {
                StatsRing(snapshot: stats.snapshot)
                    .frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 7) {
                    legendRow(.green,  "Good",       stats.snapshot.goodSeconds)
                    legendRow(.yellow, "Borderline", stats.snapshot.borderlineSeconds)
                    legendRow(.red,    "Poor",       stats.snapshot.poorSeconds)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Tracked \(timeString(stats.snapshot.totalSeconds)) · avg \(String(format: "%.0f°", stats.snapshot.averageDeviation)) from optimum")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { stats.reset() }
                    .controlSize(.small)
            }
        }
    }

    private func legendRow(_ color: Color, _ label: String, _ seconds: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption)
            Spacer()
            Text(timeString(seconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func timeString(_ s: Double) -> String {
        let secs = Int(s.rounded())
        let h = secs / 3600, m = (secs % 3600) / 60, sec = secs % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
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
                    stats.flush()
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

            Toggle("Sound", isOn: $settings.soundEnabled)
                .font(.subheadline)

            // Sound chooser — previews the sound when you switch.
            Picker("Tone", selection: $settings.soundName) {
                ForEach(SoundService.available, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .font(.subheadline)
            .disabled(!settings.soundEnabled)
            .onChange(of: settings.soundName) { _, newValue in
                sound.play(named: newValue)
            }

            // How often the ping repeats while you stay in the red zone.
            HStack {
                Text("Repeat every")
                Spacer()
                Text("\(Int(settings.soundRepeatInterval)) s").foregroundStyle(.secondary)
                Stepper("", value: $settings.soundRepeatInterval, in: 5...120, step: 5)
                    .labelsHidden()
            }
            .font(.subheadline)
            .disabled(!settings.soundEnabled)

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

/// Donut chart of time spent in each posture band. The arc lengths show *how long*
/// (good/borderline/poor), and the center shows the share of time at the optimum.
private struct StatsRing: View {
    let snapshot: StatsSnapshot

    private let lineWidth: CGFloat = 14

    var body: some View {
        let total = snapshot.totalSeconds
        let g = total > 0 ? snapshot.goodSeconds / total : 0
        let b = total > 0 ? snapshot.borderlineSeconds / total : 0
        let p = total > 0 ? snapshot.poorSeconds / total : 0

        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

            arc(from: 0,       to: g,       color: .green)
            arc(from: g,       to: g + b,   color: .yellow)
            arc(from: g + b,   to: g + b + p, color: .red)

            VStack(spacing: 1) {
                Text(total > 0 ? "\(Int((g * 100).rounded()))%" : "—")
                    .font(.title3.bold().monospacedDigit())
                Text("optimal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func arc(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: CGFloat(min(from, to)), to: CGFloat(max(from, to)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))   // start at 12 o'clock
    }
}
