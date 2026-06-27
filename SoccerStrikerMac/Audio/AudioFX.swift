import Foundation
import AVFoundation

/// 効果音の再生。
///   - 環境音(スタジアム)・歓声は **音源ファイル**(Resources/audio)を AVAudioPlayer で再生
///   - キック/ホイッスル/チャンス合図は **プログラム合成**(AVAudioEngine)で再生（専用素材が無いため）
@MainActor
final class AudioFX {
    // 合成音（AVAudioEngine）
    private let engine = AVAudioEngine()
    private let fmt: AVAudioFormat
    private let sr: Double
    private var pool: [AVAudioPlayerNode] = []
    private var rr = 0
    private var kickBuf: AVAudioPCMBuffer!
    private var whistleBuf: AVAudioPCMBuffer!
    private var chanceCueBuf: AVAudioPCMBuffer!
    private var started = false

    // 音源ファイル（AVAudioPlayer）
    private var stadium: AVAudioPlayer?   // 試合中の環境音（ループ）
    private var cheer: AVAudioPlayer?     // 得点/セーブ時の歓声

    init() {
        fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        sr = fmt.sampleRate
        for _ in 0..<6 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: fmt)
            pool.append(node)
        }
        buildBuffers()
        stadium = Self.load("stadium", loop: true, volume: 0.5)
        cheer = Self.load("cheer", loop: false, volume: 0.9)
    }

    func start() {
        guard !started else { return }
        do {
            try engine.start()
            for n in pool { n.play() }
            started = true
        } catch {
            NSLog("[AudioFX] engine start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        stadium?.stop()
        cheer?.stop()
        for n in pool { n.stop() }
        engine.stop()
        started = false
    }

    // MARK: - イベント

    func kick()      { play(kickBuf, gain: 0.9) }
    func whistle()   { play(whistleBuf) }
    func chanceCue() { play(chanceCueBuf) }

    func startAmbient() {
        stadium?.currentTime = 0
        stadium?.play()
    }

    func goal() {
        cheer?.currentTime = 0
        cheer?.volume = 0.95
        cheer?.play()
    }

    func save() {
        cheer?.currentTime = 0
        cheer?.volume = 0.7
        cheer?.play()
    }

    func conceded() { play(whistleBuf) }

    // MARK: - ファイル読み込み

    private static func load(_ name: String, loop: Bool, volume: Float) -> AVAudioPlayer? {
        let url = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "audio")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3")
        guard let url else {
            NSLog("[AudioFX] audio file not found: \(name).mp3")
            return nil
        }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.numberOfLoops = loop ? -1 : 0
        p?.volume = volume
        p?.prepareToPlay()
        return p
    }

    // MARK: - 合成音

    private func play(_ buf: AVAudioPCMBuffer?, gain: Float = 1) {
        guard started, let buf else { return }
        let node = pool[rr]
        rr = (rr + 1) % pool.count
        node.volume = gain
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    private func buildBuffers() {
        kickBuf = render(0.18) { t, _ in
            let env = expf(-Float(t) * 28)
            let tone = sinf(2 * .pi * 110 * Float(t)) * env
            let click = t < 0.02 ? Float.random(in: -1...1) * expf(-Float(t) * 200) : 0
            return (tone * 0.9 + click * 0.5) * 0.6
        }
        whistleBuf = render(0.45) { t, _ in
            let f = 2550 + sinf(2 * .pi * 16 * Float(t)) * 120
            let attack = min(Float(t) / 0.02, 1)
            let release = t > 0.30 ? max(0, 1 - Float(t - 0.30) / 0.15) : 1
            let env = attack * release
            return (sinf(2 * .pi * f * Float(t)) + sinf(2 * .pi * f * 2 * Float(t)) * 0.3) * env * 0.4
        }
        chanceCueBuf = render(0.34) { t, _ in
            let b1 = (t < 0.12) ? sinf(2 * .pi * 880 * Float(t)) : 0
            let b2 = (t > 0.16 && t < 0.30) ? sinf(2 * .pi * 1320 * Float(t)) : 0
            return (b1 + b2) * expf(-fmodf(Float(t), 0.16) * 8) * 0.35
        }
    }

    private func render(_ seconds: Double, _ fill: (Double, Int) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        let chans = Int(fmt.channelCount)
        guard let data = buf.floatChannelData else { return buf }
        for i in 0..<Int(frames) {
            let s = fill(Double(i) / sr, i)
            for c in 0..<chans { data[c][i] = s }
        }
        return buf
    }
}
