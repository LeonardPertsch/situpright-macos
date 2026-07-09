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
            .disabled(!(settings.soundEnabled || settings.bassEnabled))

            Toggle("Bass pulse", isOn: $settings.bassEnabled)
                .font(.subheadline)
                .onChange(of: settings.bassEnabled) { _, on in
                    if on { sound.playLowPulse(frequency: settings.bassFrequency) }
                }

            HStack {
                Text("Frequency")
                Spacer()
                Text("\(Int(settings.bassFrequency)) Hz").foregroundStyle(.secondary)
                Stepper("", value: $settings.bassFrequency, in: 25...120, step: 1)
                    .labelsHidden()
            }
            .font(.subheadline)
            .disabled(!settings.bassEnabled)
            .onChange(of: settings.bassFrequency) { _, hz in
                if settings.bassEnabled { sound.playLowPulse(frequency: hz) }
            }

            Text("AirPods can't truly vibrate; a deep tone is faint on small drivers.")
                .font(.caption2)
                .foregroundStyle(.secondary)

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

/// Donut chart of time spent in each posture band. The arc proportions show *how long*
/// (good/borderline/poor) via a soft green→yellow→red gradient, and the center shows the
/// share of time at the optimum. It draws on smoothly whenever the popover appears.
private struct StatsRing: View {

    let snapshot: StatsSnapshot

    private let lineWidth: CGFloat = 15

    // Segment colors (match the menu bar palette; green reads as "optimal" in a chart).
    private let green  = Color(red: 0.30, green: 0.80, blue: 0.42)
    private let yellow = Color(red: 1.00, green: 0.80, blue: 0.00)
    private let red    = Color(red: 1.00, green: 0.13, blue: 0.13)

    @State private var progress: CGFloat = 0   // drives the draw-on animation

    var body: some View {
        let total = snapshot.totalSeconds
        let goodShare = total > 0 ? snapshot.goodSeconds / total : 0

        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

            // Single ring stroked with an angular gradient → colors blend softly at the
            // segment boundaries instead of switching hard.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(gradient: Gradient(stops: gradientStops()), center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))   // start at 12 o'clock
                .animation(.easeInOut(duration: 0.55), value: snapshot)

            VStack(spacing: 1) {
                Text(total > 0 ? "\(Int((goodShare * 100).rounded()))%" : "—")
                    .font(.title3.bold().monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.5), value: goodShare)
                Text("optimal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { progress = 1 } }
        .onDisappear { progress = 0 }   // re-draw next time the popover opens
    }

    /// Builds gradient stops with a small blend band around each boundary. Locations are
    /// clamped to be monotonic so tiny/empty segments never break the gradient.
    private func gradientStops() -> [Gradient.Stop] {
        let total = snapshot.totalSeconds
        guard total > 0 else {
            return [Gradient.Stop(color: .clear, location: 0),
                    Gradient.Stop(color: .clear, location: 1)]
        }
        let g = snapshot.goodSeconds / total
        let b = snapshot.borderlineSeconds / total
        let blend = 0.03
        // Seam color = midpoint of red and green, placed at the 0/1 wrap point so the
        // top of the ring blends red→green instead of showing a hard edge.
        let seam = Color(red: 0.65, green: 0.465, blue: 0.275)
        let raw: [(Color, Double)] = [
            (seam,   0),
            (green,  blend),
            (green,  g - blend),
            (yellow, g + blend),
            (yellow, g + b - blend),
            (red,    g + b + blend),
            (red,    1 - blend),
            (seam,   1),
        ]
        var last = 0.0
        return raw.map { (color, loc) in
            let clamped = max(last, min(1, loc))
            last = clamped
            return Gradient.Stop(color: color, location: clamped)
        }
    }
}
