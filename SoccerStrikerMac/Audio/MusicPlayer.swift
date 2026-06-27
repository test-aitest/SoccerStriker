import Foundation
import AVFoundation

/// タイトル画面など、画面に紐づく BGM をループ再生する軽量プレイヤー。
@MainActor
@Observable
final class MusicPlayer {
    private var player: AVAudioPlayer?

    /// `Resources/audio/<name>.mp3` を読み込む。
    init(resource name: String, volume: Float = 0.6) {
        let url = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "audio")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3")
        guard let url else {
            NSLog("[MusicPlayer] not found: \(name).mp3")
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = volume
        player?.prepareToPlay()
    }

    func play() {
        player?.currentTime = 0
        player?.play()
    }

    func stop() {
        player?.stop()
    }
}
