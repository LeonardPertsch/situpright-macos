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
            button.image = templateImage()
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

    private func baseSymbol() -> NSImage? {
        NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: "Posture")
            ?? NSImage(systemSymbolName: "person.fill", accessibilityDescription: "Posture")
    }

    /// Template image adapts to the menu bar (white on dark, black on light) — used for
    /// "good" posture so it looks like a normal, always-visible icon.
    private func templateImage() -> NSImage? {
        let img = baseSymbol()
        img?.isTemplate = true
        return img
    }

    /// Bakes the color into the SF Symbol via a palette configuration. This is the only
    /// reliable way to tint a menu bar icon — `contentTintColor` is ignored for status
    /// item buttons using template images.
    private func coloredImage(_ color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        let img = baseSymbol()?.withSymbolConfiguration(config)
        img?.isTemplate = false
        return img
    }

    /// Maps the current app state to the menu bar color:
    /// gray (unavailable), white (good), yellow (borderline), red + pulsing (poor).
    private func updateIcon() {
        guard let button = statusItem.button else { return }

        var shouldPulse = false
        let trackingLive = service.isTracking && service.status == .active

        if !trackingLive || !detector.isCalibrated {
            // Gray whenever tracking is off, headphones are gone, or not yet calibrated.
            button.image = coloredImage(.systemGray)
        } else {
            switch detector.state {
            case .good:        button.image = templateImage()               // adaptive white
            case .borderline:  button.image = coloredImage(.systemYellow)
            case .poor:        button.image = coloredImage(.systemRed); shouldPulse = true
            case .unavailable: button.image = coloredImage(.systemGray)
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
            // ~1.1s per pulse cycle.
            self.pulsePhase += (2 * .pi) / (30.0 * 1.1)
            let eased = (sin(self.pulsePhase) + 1) / 2      // 0...1
            button.alphaValue = 0.35 + 0.65 * eased          // 0.35...1.0
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
