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

    init(settings: SettingsStore,
         service: HeadphoneMotionService,
         detector: PostureDetector) {
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
        popover.contentSize = NSSize(width: 300, height: 460)
        popover.contentViewController = NSHostingController(
            rootView: PosturePopoverView(
                settings: settings,
                service: service,
                detector: detector
            )
        )

        // Live icon updates: any change to tracking status, connection, calibration,
        // or posture state re-tints the menu bar icon.
        service.$status.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        service.$isConnected.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        service.$isTracking.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        detector.$state.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        detector.$isCalibrated.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)

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

    /// Maps the current app state to the menu bar color:
    /// gray (unavailable), white (good), yellow (borderline), red + pulsing (poor).
    private func updateIcon() {
        guard let button = statusItem.button else { return }

        var shouldPulse = false
        let trackingLive = service.isTracking && service.status == .active

        if !trackingLive || !detector.isCalibrated {
            // Gray whenever tracking is off, headphones are gone, or not yet calibrated.
            button.image = symbolImage(color: .systemGray, weight: .regular)
        } else {
            switch detector.state {
            case .good:        button.image = symbolImage(color: nil, weight: .regular)              // subtle adaptive white
            case .borderline:  button.image = symbolImage(color: Self.vividYellow, weight: .bold)    // bold gold
            case .poor:        button.image = symbolImage(color: Self.vividRed, weight: .heavy); shouldPulse = true
            case .unavailable: button.image = symbolImage(color: .systemGray, weight: .regular)
            }
        }

        if shouldPulse {
            startPulsing()
        } else {
            stopPulsing()
        }
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
