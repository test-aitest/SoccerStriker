import Foundation
import Observation
import SoccerShared
import WebSceneKit
import QuartzCore
import AppKit
import simd

/// 試合のオーケストレーション層。
///   - `SoccerEngine` を 60Hz で回す（両チームとも AI で自動進行）
///   - 各フレームの状態を `WebSceneBridge` 経由で Three.js へ送る
///   - 要所で「人間のチャンス」を割り込ませる：
///       * 攻撃＝シュートチャンス（成功で 100% ゴール）
///       * 守備＝相手シュートのセーブチャンス（成功で防ぐ）
///     ゲージはチャンスごとに「タイミング（当たりゾーン）」と「連打パワー溜め」が交互。
@MainActor
@Observable
final class GameModel {
    let bridge = WebSceneBridge()
    private let engine = SoccerEngine()
    private weak var server: NetworkServer?

    private(set) var homeScore = 0
    private(set) var awayScore = 0
    private(set) var lastEventLabel = ""

    // 人間チャンスの状態（SwiftUI ゲージが参照）。
    enum Phase { case play, chance }
    private(set) var phase: Phase = .play
    private(set) var chance: Chance?

    private let audio = AudioFX()

    private var timer: Timer?
    private var lastTickHost: CFTimeInterval = 0
    private var pendingKick: KickEvent?
    private var triggerCooldown: Float = 1.0   // チャンス連発防止
    private var chanceCounter = 0              // ゲージ種類の交互切替
    private var prevBallSpeed: Float = 0       // キック検出用
    private var prevHome = 0                   // 得点演出の差分検出
    private var prevAway = 0

    init(server: NetworkServer? = nil) {
        self.server = server
        server?.onKick = { [weak self] kick in
            self?.pendingKick = kick
        }
    }

    func start() {
        guard timer == nil else { return }
        engine.resetFormation(kickoffSide: .home)
        prevHome = 0; prevAway = 0
        lastTickHost = CACurrentMediaTime()
        audio.start()
        audio.startAmbient()
        audio.whistle()   // キックオフ
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        audio.stop()
    }

    /// キーボードからのデバッグ振り（iPhone なしで動作確認）。チャンス中は「振り」として消費される。
    func debugKick() {
        pendingKick = KickEvent(
            seq: 0, tMono: DispatchTime.now().uptimeNanoseconds,
            kind: .shoot, power: 0.9, aim: 0, loft: 0.1
        )
    }

    // MARK: - Loop

    private func tick() {
        let now = CACurrentMediaTime()
        var dt = Float(now - lastTickHost)
        lastTickHost = now
        dt = min(max(dt, 0), 1.0 / 20.0)

        switch phase {
        case .play:
            pendingKick = nil  // チャンス外の振りは無視
            let beforeSpeed = simd_length(engine.ball.vel)
            engine.tick(dt: dt)
            let afterSpeed = simd_length(engine.ball.vel)
            if afterSpeed - beforeSpeed > 5 { audio.kick() }   // 蹴った瞬間
            syncScore()
            forwardOutcome(engine.lastOutcome)
            if triggerCooldown > 0 {
                triggerCooldown -= dt
            } else {
                detectChance()
            }
        case .chance:
            updateChance(dt: dt)
        }
        reactToScore()
        pushState()
    }

    /// スコアの増分に応じてゴール/失点の効果音を鳴らす。
    private func reactToScore() {
        if homeScore > prevHome { audio.goal(); prevHome = homeScore }
        if awayScore > prevAway { audio.conceded(); prevAway = awayScore }
    }

    private func syncScore() {
        homeScore = engine.homeScore
        awayScore = engine.awayScore
    }

    /// エンジン内部で起きた結果（主に枠外など）を演出/振動へ。
    private func forwardOutcome(_ outcome: GoalEvent.Outcome?) {
        guard let outcome, outcome == .miss else { return }
        lastEventLabel = "枠外"
    }

    // MARK: - Chance

    private func detectChance() {
        if engine.homeShotChanceReady {
            startChance(kind: .shot)
        } else if engine.incomingShotOnGoal {
            startChance(kind: .save)
        }
    }

    private func startChance(kind: Chance.Kind) {
        chanceCounter += 1
        let gauge: Chance.Gauge = (chanceCounter % 2 == 0) ? .power : .timing
        var c = Chance(kind: kind, gauge: gauge)
        c.timeLeft = (gauge == .power) ? 2.6 : 2.2
        // タイミング当たりゾーン（中央付近・幅広めで気持ちよく）。
        c.sweetLo = 0.40
        c.sweetHi = 0.60
        chance = c
        phase = .chance
        pendingKick = nil
        lastEventLabel = ""
        audio.chanceCue()
        // iPhone に「今だ！」の合図（軽い振動）。
        server?.sendGoal(GoalEvent(outcome: .touch, intensity: 0.6, teamScore: homeScore, opponentScore: awayScore))
    }

    private func updateChance(dt: Float) {
        guard var c = chance else { phase = .play; return }

        // 結果表示中はホールドしてから復帰。
        if c.resolved {
            c.resultHold -= dt
            chance = c
            if c.resultHold <= 0 { finishChance() }
            return
        }

        c.timeLeft -= dt
        if c.flash > 0 { c.flash -= dt }

        switch c.gauge {
        case .timing:
            // マーカーが 0↔1 を往復。
            let sweep: Float = 1.25
            c.progress += c.markerDir * sweep * dt
            if c.progress >= 1 { c.progress = 1; c.markerDir = -1 }
            if c.progress <= 0 { c.progress = 0; c.markerDir = 1 }
        case .power:
            // 放っておくと少しずつ減る → 振り続ける必要がある。
            c.charge = max(0, c.charge - 0.14 * dt)
        }

        // 振り（KickEvent / キーボード）を消費。
        if pendingKick != nil {
            pendingKick = nil
            switch c.gauge {
            case .timing:
                let ok = c.progress >= c.sweetLo && c.progress <= c.sweetHi
                resolve(&c, success: ok)
            case .power:
                c.charge = min(1, c.charge + 0.17)
                c.flash = 0.16
                if c.charge >= 1 { resolve(&c, success: true) }
            }
        }

        if !c.resolved && c.timeLeft <= 0 {
            switch c.gauge {
            case .power:  resolve(&c, success: c.charge >= 0.7)
            case .timing: resolve(&c, success: false)
            }
        }

        chance = c
    }

    private func resolve(_ c: inout Chance, success: Bool) {
        c.resolved = true
        c.success = success
        c.resultHold = 1.1

        let out: GoalEvent.Outcome
        switch c.kind {
        case .shot:
            if success {
                engine.awardGoal(to: .home)
                lastEventLabel = "ナイスシュート！ GOAL!!"
                out = .goal
            } else {
                engine.clearBall(towardZ: 1)   // 相手 GK がキャッチ → 自陣側へ
                lastEventLabel = "シュート失敗…"
                out = .save
            }
        case .save:
            if success {
                engine.clearBall(towardZ: -1)  // 前方へ大きくクリア
                lastEventLabel = "ナイスセーブ！"
                audio.save()
                out = .save
            } else {
                engine.awardGoal(to: .away)
                lastEventLabel = "失点…"
                out = .conceded
            }
        }
        syncScore()
        let intensity: Float = (out == .goal || out == .conceded) ? 1.0 : 0.5
        server?.sendGoal(GoalEvent(outcome: out, intensity: intensity, teamScore: homeScore, opponentScore: awayScore))
    }

    private func finishChance() {
        chance = nil
        phase = .play
        triggerCooldown = 1.6
        lastEventLabel = ""
    }

    // MARK: - Render bridge

    private func pushState() {
        let b = engine.ball
        var playersPayload: [[String: Any]] = []
        playersPayload.reserveCapacity(engine.players.count)
        for p in engine.players {
            playersPayload.append([
                "id": p.id,
                "side": p.side.rawValue,
                "keeper": p.isKeeper,
                "x": Double(p.pos.x),
                "z": Double(p.pos.y),   // SIMD2.y = ピッチ縦(z)
                "ctrl": p.id == engine.controlledPlayerID,
            ])
        }
        bridge.send(type: "state", payload: [
            "ball": ["x": Double(b.pos.x), "y": Double(b.pos.y), "z": Double(b.pos.z)],
            "players": playersPayload,
            "home": engine.homeScore,
            "away": engine.awayScore,
        ])
    }
}

/// 人間チャンスの状態。SwiftUI のゲージはこの値を描画する。
struct Chance {
    enum Kind { case shot, save }
    enum Gauge { case power, timing }

    var kind: Kind
    var gauge: Gauge
    var progress: Float = 0      // timing: マーカー位置 0…1
    var markerDir: Float = 1
    var charge: Float = 0        // power: 溜め 0…1
    var sweetLo: Float = 0.4
    var sweetHi: Float = 0.6
    var timeLeft: Float = 2.0
    var flash: Float = 0         // 連打ヒットの一瞬の光り
    var resolved = false
    var success: Bool?
    var resultHold: Float = 0

    var title: String {
        switch (kind, gauge) {
        case (.shot, .timing): return "シュートチャンス！ ゾーンで振れ"
        case (.shot, .power):  return "シュートチャンス！ 連打でパワー溜め"
        case (.save, .timing): return "ピンチ！ ゾーンで振ってセーブ"
        case (.save, .power):  return "ピンチ！ 連打で弾き返せ"
        }
    }
}
