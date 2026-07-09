import AVFoundation

/// Plays the character's sound effect.
///
/// The `AVAudioPlayer` is created once and retained — a player that goes out of
/// scope stops immediately, which is the classic "no sound" bug here.
@MainActor
final class SoundPlayer {
    private let player: AVAudioPlayer?

    init(resource: String, withExtension ext: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            self.player = nil
            return
        }
        player.prepareToPlay()
        self.player = player
    }

    /// Restart from the beginning, so rapid re-triggers don't play a half clip.
    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    func stop() {
        player?.stop()
    }
}
