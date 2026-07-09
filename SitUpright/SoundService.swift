import AppKit
import AVFoundation

/// Plays short, subtle alert sounds.
///
/// On macOS, both `NSSound` and `AVAudioEngine` play through the shared system output and
/// **mix** with whatever else is playing — they do not interrupt, pause, or duck other audio
/// (music, calls, videos). There is no AVAudioSession to configure as on iOS.
final class SoundService {

    /// Curated list of short built-in macOS system sounds the user can pick from.
    static let available = ["Tink", "Pop", "Ping", "Glass", "Morse", "Submarine", "Funk", "Hero", "Sosumi"]

    // Cache one NSSound per name so repeated playback has no load latency.
    private var cache: [String: NSSound] = [:]

    func play(named name: String) {
        let sound = cache[name] ?? NSSound(named: name)
        guard let sound else {
            NSSound.beep()   // fallback if the named sound is unavailable
            return
        }
        cache[name] = sound
        sound.stop()         // guarantee a retrigger even if still playing
        sound.play()
    }

    // MARK: - Low-frequency pulse

    // NOTE: AirPods have no haptic motor, so this can't produce real vibration. It plays a
    // genuine low sine tone; at ~36 Hz the tiny AirPods drivers barely reproduce it, so it is
    // faint/inaudible there. Larger headphones (AirPods Max, over-ears) render deep bass better.

    private let sampleRate = 44_100.0
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    private func ensureEngine() -> (AVAudioEngine, AVAudioPlayerNode)? {
        if let engine, let player { return (engine, player) }
        let e = AVAudioEngine()
        let p = AVAudioPlayerNode()
        e.attach(p)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return nil }
        e.connect(p, to: e.mainMixerNode, format: fmt)
        do {
            try e.start()
        } catch {
            NSLog("SitUpright: bass engine failed to start: \(error.localizedDescription)")
            return nil
        }
        engine = e
        player = p
        return (e, p)
    }

    /// Plays a short low sine "thump" at `frequency` Hz with a soft attack/release envelope
    /// (so there's no click). Synthesized on the fly and mixed into the system output.
    func playLowPulse(frequency: Double, duration: Double = 0.6) {
        guard let (engine, player) = ensureEngine() else { return }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: fmt,
                                            frameCapacity: AVAudioFrameCount(duration * sampleRate)) else { return }

        let n = Int(duration * sampleRate)
        buffer.frameLength = AVAudioFrameCount(n)
        guard let channels = buffer.floatChannelData else { return }

        let twoPiF = 2.0 * Double.pi * frequency
        let attack = 0.02 * sampleRate     // 20 ms fade-in
        let release = 0.10 * sampleRate    // 100 ms fade-out
        for i in 0..<n {
            let t = Double(i)
            var amp = 1.0
            if t < attack { amp = t / attack }
            else if Double(n) - t < release { amp = (Double(n) - t) / release }
            // Low frequencies are perceptually quiet, so drive it fairly hard.
            let sample = Float(sin(twoPiF * t / sampleRate) * amp * 0.85)
            channels[0][i] = sample
            channels[1][i] = sample
        }

        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
