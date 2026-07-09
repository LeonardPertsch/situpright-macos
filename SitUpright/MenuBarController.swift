import AppKit
import SwiftUI
import Combine

/// Owns the `NSStatusItem` (the menu bar presence) and the popover. Subscribes to
/// the service + detector and re-renders the menu bar icon color live.
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    private let settings: SettingsStore
    private let service: HeadphoneMotionService
    private let detector: PostureDetector

    private var cancellables = Set<AnyCancellable>()

    // Drives the pulsing effect while posture is poor.
    private var pulseTimer: Timer?
    private var pulsePhase: Double = 0

    // Last color drawn, so we can skip rebuilding identical images on every sample.
    private var lastImageColor: NSColor?

    init(settings: SettingsStore,
         service: HeadphoneMotionService,
         detector: PostureDetector,
         sound: SoundService,
         stats: StatsStore) {
        self.settings = settings
        self.service = service
        self.detector = detector

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = symbolImage(color: nil, weight: .regular)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "SitUpright — posture reminder"
        }

        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: PosturePopoverView(
                settings: settings,
                service: service,
                detector: detector,
                sound: sound,
                stats: stats
            )
        )
        // Let the popover grow/shrink as the collapsible settings sections open and close.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        // Live icon updates: any change to tracking status, connection, calibration,
        // or posture state re-tints the menu bar icon.
        service.$status.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        service.$isConnected.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        service.$isTracking.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        detector.$state.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        detector.$isCalibrated.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        // Continuous deviation drives the fluid color blend.
        detector.$deviationDegrees.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)

        updateIcon()
    }

    deinit {
        pulseTimer?.invalidate()
    }

    // MARK: - Icon

    private static let symbolName = "figure.seated.side"
    private static let iconPointSize: CGFloat = 15

    // Punchy, high-saturation warning colors so the icon really stands out.
    private static let vividYellow = NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1)
    private static let vividRed    = NSColor(srgbRed: 1.00, green: 0.13, blue: 0.13, alpha: 1)

    private func baseSymbol() -> NSImage? {
        NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: "Posture")
            ?? NSImage(systemSymbolName: "person.fill", accessibilityDescription: "Posture")
    }

    /// Builds the menu bar image.
    /// - `color == nil` → template image that adapts to the bar (white on dark) for the
    ///   subtle "good" state.
    /// - `color != nil` → color baked into the SF Symbol via a palette configuration
    ///   (the only reliable way to tint a status item icon). A heavier `weight` thickens
    ///   the strokes so warning states grab attention.
    private func symbolImage(color: NSColor?, weight: NSFont.Weight) -> NSImage? {
        let base = baseSymbol()
        if let color {
            let cfg = NSImage.SymbolConfiguration(pointSize: Self.iconPointSize, weight: weight)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            let img = base?.withSymbolConfiguration(cfg)
            img?.isTemplate = false
            return img
        } else {
            let cfg = NSImage.SymbolConfiguration(pointSize: Self.iconPointSize, weight: weight)
            let img = base?.withSymbolConfiguration(cfg)
            img?.isTemplate = true
            return img
        }
    }

    /// Updates the menu bar icon. Gray when unavailable; otherwise a color blended
    /// continuously from the smoothed deviation angle (white → yellow → red) so it
    /// morphs smoothly instead of snapping at thresholds. Red also pulses.
    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let trackingLive = service.isTracking && service.status == .active

        guard trackingLive && detector.isCalibrated else {
            // Gray whenever tracking is off, headphones are gone, or not yet calibrated.
            lastImageColor = nil
            button.image = symbolImage(color: .systemGray, weight: .regular)
            stopPulsing()
            return
        }

        let color = trackingColor(deviation: detector.deviationDegrees)
        // Only rebuild the image when the color visibly changed (samples arrive fast).
        if !colorsClose(lastImageColor, color) {
            lastImageColor = color
            button.image = symbolImage(color: color, weight: .bold)
        }

        // Pulse only once fully into the poor zone.
        if detector.state == .poor { startPulsing() } else { stopPulsing() }
    }

    /// Blends the icon color from the deviation angle. The yellow band is intentionally
    /// wide so the icon lingers on yellow well before it turns red.
    private func trackingColor(deviation d: Double) -> NSColor {
        let warn = settings.effectiveWarning
        let bad = settings.effectiveBad
        let good = resolvedGoodColor()

        let whiteEnd = warn * 0.5                       // pure "good" below this
        let yellowStart = warn                          // full yellow reached here
        let yellowHoldEnd = warn + 0.75 * (bad - warn)  // stays yellow until here (long band)

        if d <= whiteEnd {
            return good
        } else if d < yellowStart {
            return blend(good, Self.vividYellow, (d - whiteEnd) / (yellowStart - whiteEnd))
        } else if d <= yellowHoldEnd {
            return Self.vividYellow
        } else if d < bad {
            return blend(Self.vividYellow, Self.vividRed, (d - yellowHoldEnd) / (bad - yellowHoldEnd))
        } else {
            return Self.vividRed
        }
    }

    /// "Good" endpoint that stays visible: white on the dark menu bar, dark on a light one.
    private func resolvedGoodColor() -> NSColor {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? .white : NSColor(white: 0.15, alpha: 1)
    }

    private func blend(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
        let ca = a.usingColorSpace(.sRGB) ?? a
        let cb = b.usingColorSpace(.sRGB) ?? b
        let tt = CGFloat(max(0, min(1, t)))
        return NSColor(srgbRed: ca.redComponent + (cb.redComponent - ca.redComponent) * tt,
                       green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * tt,
                       blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * tt,
                       alpha: 1)
    }

    private func colorsClose(_ a: NSColor?, _ b: NSColor) -> Bool {
        guard let a = a?.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
        let d = abs(a.redComponent - b.redComponent)
            + abs(a.greenComponent - b.greenComponent)
            + abs(a.blueComponent - b.blueComponent)
        return d < 0.015
    }

    // MARK: - Pulsing (poor posture)

    /// Softly oscillates the icon's opacity to draw attention while slouching.
    private func startPulsing() {
        guard pulseTimer == nil else { return }
        pulsePhase = 0
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            // ~0.9s per pulse cycle — a bit faster and deeper so it reads as an alert.
            self.pulsePhase += (2 * .pi) / (30.0 * 0.9)
            let eased = (sin(self.pulsePhase) + 1) / 2      // 0...1
            button.alphaValue = 0.15 + 0.85 * eased          // 0.15...1.0
        }
        RunLoop.main.add(timer, forMode: .common)   // keep pulsing while menus are open
        pulseTimer = timer
    }

    private func stopPulsing() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        statusItem.button?.alphaValue = 1.0
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
