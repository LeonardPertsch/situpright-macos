import AppKit

/// Plays a short, subtle alert sound.
///
/// On macOS, `NSSound` plays through the shared system output and **mixes** with whatever
/// else is playing — it does not interrupt, pause, or duck other audio (music, calls,
/// videos). There is no AVAudioSession to configure as on iOS, so a plain `NSSound` is
/// exactly the "quick beep that doesn't interrupt other sources" we want.
final class SoundService {

    // "Tink" is one of the shortest built-in system sounds. Preloaded so there's no
    // latency on the first play. Swap the name for another system sound if you prefer
    // (e.g. "Pop", "Ping", "Morse").
    private let sound = NSSound(named: "Tink")

    func playPosturePing() {
        guard let sound else {
            NSSound.beep()   // fallback if the named sound is unavailable
            return
        }
        sound.stop()         // guarantee a retrigger even if still playing
        sound.play()
    }
}
