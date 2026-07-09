import AppKit

/// Plays short, subtle alert sounds.
///
/// On macOS, `NSSound` plays through the shared system output and **mixes** with whatever
/// else is playing — it does not interrupt, pause, or duck other audio (music, calls,
/// videos). There is no AVAudioSession to configure as on iOS, so a plain `NSSound` is
/// exactly the "quick beep that doesn't interrupt other sources" we want.
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
}
