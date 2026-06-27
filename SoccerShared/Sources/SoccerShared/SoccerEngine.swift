import Foundation
import simd

/// チームの陣営。`home` がプレイヤー（iPhone 操作）側。
public enum TeamSide: String, Codable, Sendable {
    case home   // プレイヤー側：-z のゴールを攻める
    case away   // CPU 側：+z のゴールを攻める

    public var attackingGoalZ: Float {
        self == .home ? Pitch.enemyGoalZ : Pitch.ownGoalZ
    }
    public var defendingGoalZ: Float {
        self == .home ? Pitch.ownGoalZ : Pitch.enemyGoalZ
    }
}

/// 選手 1 人の状態。座標は XZ 平面（メートル）。
public struct PlayerState: Sendable {
    public let id: Int
    public let side: TeamSide
    public let isKeeper: Bool
    public var pos: SIMD2<Float>      // x, z
    public var homePos: SIMD2<Float>  // フォーメーション基準位置
    public var vel: SIMD2<Float> = .zero

    public init(id: Int, side: TeamSide, isKeeper: Bool, pos: SIMD2<Float>, homePos: SIMD2<Float>) {
        self.id = id
        self.side = side
        self.isKeeper = isKeeper
        self.pos = pos
        self.homePos = homePos
    }
}

/// ボールの状態。y は高さ。
public struct BallState: Sendable {
    public var pos: SIMD3<Float> = SIMD3(0, BallPhysics.radius, 0)
    public var vel: SIMD3<Float> = .zero
}

/// 4vs4 サッカーの最小シミュレーション。
///
/// 役割分担：
///   - `tick(dt:)` で物理 + 簡易 AI を 1 ステップ進める。
///   - `applyKick(_:)` で iPhone から来た蹴りを「操作中の選手」に適用する。
///   - `snapshot()` で Three.js へ渡す描画用スナップショットを得る。
///
/// 純 Swift（UI/ネット非依存）なので UnitTest で挙動を固定できる。
public final class SoccerEngine: @unchecked Sendable {

    public private(set) var ball = BallState()
    public private(set) var players: [PlayerState] = []
    public private(set) var homeScore = 0
    public private(set) var awayScore = 0
    /// 直近の得点などのイベント（Mac 側がフィードバック送信に使う）。
    public private(set) var lastOutcome: GoalEvent.Outcome?

    /// 操作中の選手 id（home 側でボールに最も近い者）。
    public private(set) var controlledPlayerID: Int = 0

    private let controlRadius: Float = 1.2
    private let playerSpeed: Float = 6.5
    private let keeperSpeed: Float = 4.5
    private let shootRange: Float = 13
    private var kickoffCooldown: Float = 0
    private var kickCooldown: Float = 0
    private var rngState: UInt64 = 0x9E3779B97F4A7C15

    /// home（プレイヤー側）に人間のシュートチャンスが発生している（ボール保持＋ゴール圏内）。
    /// GameModel がこれを見てタイミングゲージを起動する。AI は home の決定打を蹴らずキープする。
    public private(set) var homeShotChanceReady = false
    /// away の枠内シュートが home ゴールへ向かっている（守備=セーブチャンス）。
    public private(set) var incomingShotOnGoal = false

    public init() {
        resetFormation(kickoffSide: .home)
    }

    // MARK: - Setup

    /// キックオフ配置に戻す。`kickoffSide` がセンターでボールを持つ。
    public func resetFormation(kickoffSide: TeamSide) {
        players = []
        // 4-4 のシンプルな配置（GK + DF2 + MF1 + FW1）を各チームに。
        let formation: [(x: Float, z: Float, keeper: Bool)] = [
            (0,            Pitch.length / 2 - 1.0, true),   // GK
            (-Pitch.width / 4, Pitch.length / 4, false),    // DF L
            ( Pitch.width / 4, Pitch.length / 4, false),    // DF R
            (0,            Pitch.length / 8, false),        // MF
            (0,            1.5, false),                      // FW
        ]
        var id = 0
        for (x, z, keeper) in formation {
            // home は +z 自陣 → 配置はそのまま。away はミラー。
            let home = SIMD2<Float>(x, z)
            players.append(PlayerState(id: id, side: .home, isKeeper: keeper, pos: home, homePos: home))
            id += 1
        }
        for (x, z, keeper) in formation {
            let away = SIMD2<Float>(-x, -z)
            players.append(PlayerState(id: id, side: .away, isKeeper: keeper, pos: away, homePos: away))
            id += 1
        }
        ball = BallState()
        kickoffCooldown = 0.4
        lastOutcome = nil
        updateControlledPlayer()
    }

    // MARK: - Tick

    public func tick(dt: Float) {
        lastOutcome = nil
        homeShotChanceReady = false
        incomingShotOnGoal = false
        if kickoffCooldown > 0 { kickoffCooldown -= dt }
        if kickCooldown > 0 { kickCooldown -= dt }

        stepBall(dt: dt)
        stepPlayers(dt: dt)
        updateControlledPlayer()
        resolvePossession(dt: dt)
        detectIncomingShot()
        checkGoals()
    }

    private func stepBall(dt: Float) {
        var b = ball
        // 重力
        b.vel.y -= BallPhysics.gravity * dt
        b.pos += b.vel * dt
        // 地面バウンド
        if b.pos.y < BallPhysics.radius {
            b.pos.y = BallPhysics.radius
            if b.vel.y < 0 { b.vel.y = -b.vel.y * BallPhysics.restitution }
            // 接地時の水平摩擦
            let damp = max(0, 1 - BallPhysics.groundDamping * dt)
            b.vel.x *= damp
            b.vel.z *= damp
            if abs(b.vel.y) < 0.4 { b.vel.y = 0 }
        }
        // サイドライン反射（簡易）
        let halfW = Pitch.width / 2
        if abs(b.pos.x) > halfW {
            b.pos.x = simd_clamp(b.pos.x, -halfW, halfW)
            b.vel.x = -b.vel.x * 0.5
        }
        ball = b
    }

    private func stepPlayers(dt: Float) {
        let ballXZ = SIMD2<Float>(ball.pos.x, ball.pos.z)
        for i in players.indices {
            var p = players[i]
            let target: SIMD2<Float>
            let speed: Float

            if p.isKeeper {
                // GK は自ゴールライン上を x 追従。
                let gx = simd_clamp(ball.pos.x, -Pitch.goalWidth / 2, Pitch.goalWidth / 2)
                target = SIMD2(gx, p.homePos.y)
                speed = keeperSpeed
            } else if isClosest(player: p, to: ballXZ) {
                // 自チームでボールに最も近い選手がボールを取りに行く（両チームとも AI）。
                target = ballXZ
                speed = playerSpeed
            } else {
                // それ以外：定位置をボール方向へずらして広がる（フォーメーション維持）。
                target = biasedHome(p, ballXZ: ballXZ)
                speed = playerSpeed * 0.9
            }

            let toTarget = target - p.pos
            let d = simd_length(toTarget)
            if d > 0.05 {
                let dir = toTarget / d
                p.vel = dir * min(speed, d / dt)
            } else {
                p.vel = .zero
            }
            p.pos += p.vel * dt
            // ピッチ内にクランプ
            p.pos.x = simd_clamp(p.pos.x, -Pitch.width / 2, Pitch.width / 2)
            p.pos.y = simd_clamp(p.pos.y, -Pitch.length / 2, Pitch.length / 2)
            players[i] = p
        }
    }

    /// フォーメーション位置をボール z 方向へ少しずらした攻守バランス位置。
    private func biasedHome(_ p: PlayerState, ballXZ: SIMD2<Float>) -> SIMD2<Float> {
        var t = p.homePos
        // SIMD2: .x = ピッチ横, .y = ピッチ縦(z)
        t.y = simd_mix(p.homePos.y, ballXZ.y, 0.5)
        t.x = simd_mix(p.homePos.x, ballXZ.x, 0.3)
        return t
    }

    /// ボール保持者の AI 判断（シュート/パス/ドリブル）と人間チャンスの検知。
    private func resolvePossession(dt: Float) {
        guard kickoffCooldown <= 0 else { return }
        let ballXZ = SIMD2<Float>(ball.pos.x, ball.pos.z)

        // 支配圏内でボールに最も近い非 GK = 保持者。
        var carrier: PlayerState?
        var best = controlRadius
        for p in players where !p.isKeeper {
            let d = simd_length(p.pos - ballXZ)
            if d < best { best = d; carrier = p }
        }

        if let c = carrier {
            let goal = SIMD2<Float>(0, c.side.attackingGoalZ)
            let goalDist = simd_length(goal - c.pos)

            // home がゴール圏内に持ち込んだら、AI は蹴らず保持して人間のシュートチャンスにする。
            if c.side == .home && goalDist < shootRange {
                homeShotChanceReady = true
            } else if kickCooldown <= 0 {
                aiAct(carrier: c, goalDist: goalDist)
            }
        }

        // away GK のみ自動クリア（home ゴールは人間がセーブする）。
        for p in players where p.isKeeper && p.side == .away {
            if simd_length(p.pos - ballXZ) < controlRadius + 0.4 {
                autoKick(dir: SIMD2(0, 1), power: 0.7, loft: 0.3)
                lastOutcome = .save
            }
        }
    }

    /// AI のボール処理：近ければシュート、前方に味方がいればパス、無ければドリブル。
    private func aiAct(carrier c: PlayerState, goalDist: Float) {
        let forwardZ: Float = c.side == .home ? -1 : 1
        if goalDist < shootRange {
            // シュート：ゴールマウスへ多少のばらつきを付けて。
            let targetX = (rand() - 0.5) * Pitch.goalWidth * 0.8
            let aimPt = SIMD2<Float>(targetX, c.side.attackingGoalZ)
            shoot(from: c.pos, to: aimPt, power: 0.8 + rand() * 0.2, loft: 0.1)
            kickCooldown = 0.5
        } else if let mate = bestPassTarget(for: c, forwardZ: forwardZ) {
            // パス：前方の味方へ。距離に応じた強さ。
            let d = simd_length(mate.pos - c.pos)
            let power = simd_clamp(d / 22, 0.35, 0.7)
            shoot(from: c.pos, to: mate.pos, power: power, loft: 0.08)
            kickCooldown = 0.35
        } else {
            // ドリブル：ゴール方向へ小さく運ぶ（連続タッチ）。
            shoot(from: c.pos, to: c.pos + SIMD2(0, forwardZ * 4), power: 0.28, loft: 0)
            kickCooldown = 0.3
        }
    }

    /// 前方（攻める側）にいて射程内の最も進んだ味方を返す。
    private func bestPassTarget(for c: PlayerState, forwardZ: Float) -> PlayerState? {
        var bestMate: PlayerState?
        var bestAdvance: Float = 2  // 最低 2m は前進している相手のみ
        for m in players where m.side == c.side && !m.isKeeper && m.id != c.id {
            let advance = (m.pos.y - c.pos.y) * forwardZ   // 攻める方向への前進量
            let dist = simd_length(m.pos - c.pos)
            if advance > bestAdvance && dist < 20 {
                bestAdvance = advance
                bestMate = m
            }
        }
        return bestMate
    }

    /// home の枠内シュートが自ゴールへ向かっているかを判定（守備チャンス用）。
    private func detectIncomingShot() {
        // +z 方向（home ゴール）へ十分速く、home 陣内を飛んでいる。
        guard ball.vel.z > 8, ball.pos.z > 2 else { return }
        let t = (Pitch.ownGoalZ - ball.pos.z) / max(ball.vel.z, 0.001)
        guard t > 0, t < 1.2 else { return }
        let xAtGoal = ball.pos.x + ball.vel.x * t
        if abs(xAtGoal) < Pitch.goalWidth / 2 + 1 {
            incomingShotOnGoal = true
        }
    }

    /// 始点→狙い点の方向へボールを蹴る。
    private func shoot(from: SIMD2<Float>, to: SIMD2<Float>, power: Float, loft: Float) {
        var dir = to - from
        dir = simd_length(dir) > 0 ? simd_normalize(dir) : SIMD2(0, -1)
        autoKick(dir: dir, power: power, loft: loft)
    }

    /// 決定論的な擬似乱数（xorshift）。0…1。テストの再現性を保つ。
    private func rand() -> Float {
        rngState ^= rngState << 13
        rngState ^= rngState >> 7
        rngState ^= rngState << 17
        return Float(rngState % 100_000) / 100_000.0
    }

    private func autoKick(dir: SIMD2<Float>, power: Float, loft: Float) {
        let speed = BallPhysics.maxShotSpeed * power
        ball.vel = SIMD3(dir.x * speed, loft * speed * 0.6, dir.y * speed)
        ball.pos.y = max(ball.pos.y, BallPhysics.radius)
    }

    private func checkGoals() {
        let halfGoalW = Pitch.goalWidth / 2
        let inWidth = abs(ball.pos.x) < halfGoalW
        let inHeight = ball.pos.y < Pitch.goalHeight
        // home が攻めるのは -z ゴール → away ゴール
        if ball.pos.z < Pitch.enemyGoalZ && inWidth && inHeight {
            homeScore += 1
            lastOutcome = .goal
            resetFormation(kickoffSide: .away)
        } else if ball.pos.z > Pitch.ownGoalZ && inWidth && inHeight {
            awayScore += 1
            lastOutcome = .conceded
            resetFormation(kickoffSide: .home)
        } else if (ball.pos.z < Pitch.enemyGoalZ || ball.pos.z > Pitch.ownGoalZ) && !inWidth {
            // 枠外（ゴールラインは越えたが幅外）：簡易的にセンターへ戻す。
            if lastOutcome == nil { lastOutcome = .miss }
            let kickoff: TeamSide = ball.pos.z < 0 ? .home : .away
            resetFormation(kickoffSide: kickoff)
        }
    }

    // MARK: - Player kick (from iPhone)

    /// iPhone の蹴りを操作中の選手に適用する。選手がボール支配圏にいなければ無視。
    @discardableResult
    public func applyKick(_ kick: KickEvent) -> Bool {
        guard let p = players.first(where: { $0.id == controlledPlayerID }) else { return false }
        let ballXZ = SIMD2<Float>(ball.pos.x, ball.pos.z)
        guard simd_length(p.pos - ballXZ) < controlRadius + 0.5 else {
            return false  // 届いていない
        }

        // 攻める方向（home は -z）を基準に、aim で左右へ振る。
        let forwardZ: Float = p.side == .home ? -1 : 1
        // aim を x オフセットに。+aim で右へ。
        var dir = SIMD2<Float>(kick.aim, forwardZ)
        dir = simd_length(dir) > 0 ? simd_normalize(dir) : SIMD2(0, forwardZ)

        // 種類ごとの強さ係数。
        //   shoot        : 強い一撃
        //   dribble      : 弱く前へ運ぶ（連続で押し進める）
        //   divingHeader : 高く飛び込む（浮き球が前提）
        let power = max(0.25, kick.power)
        let kindFactor: Float
        switch kick.kind {
        case .shoot:        kindFactor = 1.0
        case .dribble:      kindFactor = 0.35
        case .divingHeader: kindFactor = 0.85
        }
        let speed = BallPhysics.maxShotSpeed * power * kindFactor
        // ダイビングヘッドは浮き球をゴールへ叩き込むので軽い下向き、それ以外は loft 通り。
        let loftV: Float = kick.kind == .divingHeader
            ? -speed * 0.12
            : kick.loft * speed * 0.7

        ball.vel = SIMD3(dir.x * speed, loftV, dir.y * speed)
        ball.pos.y = max(ball.pos.y, BallPhysics.radius)
        lastOutcome = .touch
        return true
    }

    // MARK: - Chance resolution (人間チャンスの結果適用)

    /// チャンス成功/失敗の結果として、指定チームに得点を与えキックオフへ。
    public func awardGoal(to side: TeamSide) {
        if side == .home {
            homeScore += 1
            lastOutcome = .goal
            resetFormation(kickoffSide: .away)
        } else {
            awayScore += 1
            lastOutcome = .conceded
            resetFormation(kickoffSide: .home)
        }
    }

    /// セーブ成功/枠外などでボールを z 方向（-1=相手側 / +1=自分側）へ大きく弾く。
    public func clearBall(towardZ z: Float) {
        let speed = BallPhysics.maxShotSpeed * 0.55
        ball.vel = SIMD3((rand() - 0.5) * 6, speed * 0.35, z * speed)
        ball.pos.y = max(ball.pos.y, BallPhysics.radius)
        kickCooldown = 0.7
        lastOutcome = .save
    }

    // MARK: - Helpers

    private func updateControlledPlayer() {
        let ballXZ = SIMD2<Float>(ball.pos.x, ball.pos.z)
        var best = Float.greatestFiniteMagnitude
        var bestID = controlledPlayerID
        for p in players where p.side == .home && !p.isKeeper {
            let d = simd_length(p.pos - ballXZ)
            if d < best { best = d; bestID = p.id }
        }
        controlledPlayerID = bestID
    }

    /// `player` が自チームのフィールド選手の中でボールに最も近いか。
    private func isClosest(player: PlayerState, to point: SIMD2<Float>) -> Bool {
        var best = Float.greatestFiniteMagnitude
        var bestID = -1
        for p in players where p.side == player.side && !p.isKeeper {
            let d = simd_length(p.pos - point)
            if d < best { best = d; bestID = p.id }
        }
        return bestID == player.id
    }
}
