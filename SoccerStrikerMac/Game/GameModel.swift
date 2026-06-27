import Foundation
import Observation
import SoccerShared
import WebSceneKit
import QuartzCore
import AppKit
import SwiftUI
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
    private let brain = AgentBrain()
    /// Gemini エージェントが意図を供給できているか（HUD 表示用）。
    private(set) var aiActive = false
    private var aiTask: Task<Void, Never>?
    private let homeCountry: Country
    private let awayCountry: Country
    private let homeColorHex: String
    private let awayColorHex: String

    /// 試合中のカットイン演出（横からスライドインする選手＋見出し）。
    private(set) var cutIn: CutIn?
    private var cutInTimeLeft: Float = 0
    private var cutInSeq = 0
    private var dribbleCutInCooldown: Float = 0
    private var managerCutInCooldown: Float = 0

    private var timer: Timer?
    private var lastTickHost: CFTimeInterval = 0
    private var pendingKick: KickEvent?
    private var triggerCooldown: Float = 1.0   // チャンス連発防止
    private var chanceCounter = 0              // ゲージ種類の交互切替
    private var prevBallSpeed: Float = 0       // キック検出用
    private var prevHome = 0                   // 得点演出の差分検出
    private var prevAway = 0

    init(server: NetworkServer? = nil, home: Country = .japan, away: Country = .brazil) {
        self.server = server
        self.homeCountry = home
        self.awayCountry = away
        self.homeColorHex = home.primaryHex
        self.awayColorHex = away.primaryHex
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
        startAILoop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        aiTask?.cancel()
        aiTask = nil
        audio.stop()
    }

    // MARK: - AI エージェント（Gemini 3.5 Flash）

    /// 数秒ごとに局面を Gemini に渡し、各選手の意図を受け取ってエンジンに適用する。
    /// 応答待ちの間も 60Hz ループは直前の意図を実行し続ける。
    private func startAILoop() {
        aiTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.phase == .play {
                    let prompt = self.buildAgentPrompt()
                    if let intents = await self.brain.decide(prompt: prompt), !intents.isEmpty {
                        self.engine.setIntentions(intents)
                        self.aiActive = true
                    }
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 秒間隔
            }
        }
    }

    /// 現在の局面を Gemini への指示文に整形する。
    private func buildAgentPrompt() -> String {
        func roleName(_ r: PlayerRole) -> String {
            switch r { case .keeper: "GK"; case .defender: "DF"; case .midfielder: "MF"; case .forward: "FW" }
        }
        let b = engine.ball
        var lines: [String] = []
        for p in engine.players where !p.isKeeper {
            lines.append("  {id:\(p.id), team:\"\(p.side.rawValue)\", role:\"\(roleName(p.role))\", x:\(String(format: "%.1f", p.pos.x)), z:\(String(format: "%.1f", p.pos.y))}")
        }
        return """
        あなたはサッカーAIの監督エージェント。両チームの全フィールド選手の次の行動(意図)を決める。
        ピッチ: 横幅x=±\(Int(Pitch.width/2)), 縦z=±\(Int(Pitch.length/2))。homeは z=-\(Int(Pitch.length/2)) のゴールを攻め、awayは z=+\(Int(Pitch.length/2)) を攻める。
        ボール位置: x=\(String(format: "%.1f", b.pos.x)), z=\(String(format: "%.1f", b.pos.z))。スコア home \(engine.homeScore) - \(engine.awayScore) away。
        選手一覧:
        \(lines.joined(separator: "\n"))
        各選手に action(move/dribble/shoot/pass/mark/support/hold) と移動先 targetX,targetZ を割り当て、
        攻撃側はスペースへ走り得点を狙い、守備側は相手をmarkしゴール前を固めるように連携させること。
        passの場合は passTo に味方の id を入れる。全フィールド選手分を JSON 配列で返す。
        """
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

        updateCutIn(dt: dt)

        switch phase {
        case .play:
            pendingKick = nil  // チャンス外の振りは無視
            let beforeSpeed = simd_length(engine.ball.vel)
            engine.tick(dt: dt)
            let afterSpeed = simd_length(engine.ball.vel)
            if afterSpeed - beforeSpeed > 5 { audio.kick() }   // 蹴った瞬間
            syncScore()
            forwardOutcome(engine.lastOutcome)
            // 良いドリブルが出たらカットイン（連発防止クールダウン付き）。
            if dribbleCutInCooldown > 0 { dribbleCutInCooldown -= dt }
            if let side = engine.notableDribble, dribbleCutInCooldown <= 0 {
                let c = (side == .home) ? homeCountry : awayCountry
                showCutIn(image: c.dribbleImage, title: "NICE DRIBBLE!", color: c.primaryColor, fromLeft: side == .home)
                dribbleCutInCooldown = 6
            }
            // AI の采配が的中（パス成功/マーク奪取）したら監督カットイン。
            if managerCutInCooldown > 0 { managerCutInCooldown -= dt }
            if let side = engine.tacticSuccess, managerCutInCooldown <= 0 {
                managerCutIn(for: side)
            }
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

    /// カットインの寿命管理。
    private func updateCutIn(dt: Float) {
        guard cutIn != nil else { return }
        cutInTimeLeft -= dt
        if cutInTimeLeft <= 0 { cutIn = nil }
    }

    private func showCutIn(image: NSImage?, title: String, color: Color, fromLeft: Bool, isManager: Bool = false) {
        cutInSeq += 1
        cutIn = CutIn(id: cutInSeq, image: image, title: title, color: color, fromLeft: fromLeft, isManager: isManager)
        cutInTimeLeft = isManager ? 2.0 : 1.7
    }

    /// スコアの増分に応じてゴール/失点の効果音＋得点側の監督カットイン。
    private func reactToScore() {
        if homeScore > prevHome { audio.goal(); prevHome = homeScore; managerCutIn(for: .home) }
        if awayScore > prevAway { audio.conceded(); prevAway = awayScore; managerCutIn(for: .away) }
    }

    /// 监督「采配的中」カットイン。
    private func managerCutIn(for side: TeamSide) {
        let c = (side == .home) ? homeCountry : awayCountry
        let lines = ["TACTICS ON POINT!", "JUST AS PLANNED!", "GREAT CALL!", "GOTCHA!"]
        let text = lines[cutInSeq % lines.count]
        showCutIn(image: c.directorImage, title: text, color: c.primaryColor,
                  fromLeft: side == .home, isManager: true)
        managerCutInCooldown = 5
    }

    private func syncScore() {
        homeScore = engine.homeScore
        awayScore = engine.awayScore
    }

    /// エンジン内部で起きた結果（主に枠外など）を演出/振動へ。
    private func forwardOutcome(_ outcome: GoalEvent.Outcome?) {
        guard let outcome, outcome == .miss else { return }
        lastEventLabel = "MISS"
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
        // シュートのカットイン演出（攻撃＝自国, 守備＝相手国が横から入る）。
        switch kind {
        case .shot:
            showCutIn(image: homeCountry.shootImage, title: "SHOOT!",
                      color: homeCountry.primaryColor, fromLeft: true)
        case .save:
            showCutIn(image: awayCountry.shootImage, title: "DANGER!",
                      color: awayCountry.primaryColor, fromLeft: false)
        }
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
                lastEventLabel = "GREAT SHOT! GOAL!!"
                out = .goal
            } else {
                engine.clearBall(towardZ: 1)   // 相手 GK がキャッチ → 自陣側へ
                lastEventLabel = "SHOT MISSED…"
                out = .save
            }
        case .save:
            if success {
                engine.clearBall(towardZ: -1)  // 前方へ大きくクリア
                lastEventLabel = "GREAT SAVE!"
                audio.save()
                out = .save
            } else {
                engine.awardGoal(to: .away)
                lastEventLabel = "CONCEDED…"
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
            "homeShirt": homeColorHex,
            "homeShorts": homeCountry.secondaryHex,
            "awayShirt": awayColorHex,
            "awayShorts": awayCountry.secondaryHex,
        ])
    }
}

/// 試合中の演出カットイン（横からスライドインする選手＋見出し）。
struct CutIn: Identifiable {
    let id: Int
    let image: NSImage?
    let title: String
    let color: Color
    let fromLeft: Bool
    var isManager: Bool = false
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
        case (.shot, .timing): return "SHOOT! Swing in the zone"
        case (.shot, .power):  return "SHOOT! Mash to charge power"
        case (.save, .timing): return "DANGER! Swing in the zone to save"
        case (.save, .power):  return "DANGER! Mash to block"
        }
    }
}
