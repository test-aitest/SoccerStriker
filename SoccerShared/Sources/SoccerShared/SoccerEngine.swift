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

/// 選手の役割。攻守での振る舞いを分ける。
public enum PlayerRole: Sendable {
    case keeper, defender, midfielder, forward
}

/// 選手 1 人の状態。座標は XZ 平面（メートル）。
public struct PlayerState: Sendable {
    public let id: Int
    public let side: TeamSide
    public let isKeeper: Bool
    public let role: PlayerRole
    public var pos: SIMD2<Float>      // x, z
    public var homePos: SIMD2<Float>  // フォーメーション基準位置
    public var vel: SIMD2<Float> = .zero

    public init(id: Int, side: TeamSide, isKeeper: Bool, role: PlayerRole, pos: SIMD2<Float>, homePos: SIMD2<Float>) {
        self.id = id
        self.side = side
        self.isKeeper = isKeeper
        self.role = role
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
    /// 現在ボールを保持しているチーム（ヒステリシス付き＝cm 差で取り合わない）。
    private var possessing: TeamSide = .home

    /// AI エージェントが与えた各選手の意図（playerID → Intention）。
    /// 空ならルールベースのフォーメーションで動く（フォールバック）。
    private var intentions: [Int: Intention] = [:]
    /// AI エージェントが実際に意図を供給しているか（HUD 表示用）。
    public private(set) var aiControlled = false

    /// AI エージェントの意図をまとめて適用する。
    public func setIntentions(_ list: [Intention]) {
        guard !list.isEmpty else { return }
        for it in list { intentions[it.playerID] = it }
        aiControlled = true
    }

    /// home（プレイヤー側）に人間のシュートチャンスが発生している（ボール保持＋ゴール圏内）。
    /// GameModel がこれを見てタイミングゲージを起動する。AI は home の決定打を蹴らずキープする。
    public private(set) var homeShotChanceReady = false
    /// away の枠内シュートが home ゴールへ向かっている（守備=セーブチャンス）。
    public private(set) var incomingShotOnGoal = false
    /// 相手陣で良いドリブルが発生したチーム（カットイン演出用）。なければ nil。
    public private(set) var notableDribble: TeamSide?
    /// AI の采配が的中したチーム（パス成功／マークでの奪取）。監督カットイン用。
    public private(set) var tacticSuccess: TeamSide?

    /// 進行中のパス（成功判定用）。
    private var pendingPass: (to: Int, side: TeamSide, ttl: Float)?

    public init() {
        resetFormation(kickoffSide: .home)
    }

    // MARK: - Setup

    /// キックオフ配置に戻す。`kickoffSide` がセンターでボールを持つ。
    public func resetFormation(kickoffSide: TeamSide) {
        players = []
        let W = Pitch.width, L = Pitch.length
        // 横幅を使う配置：4 人を左右 4 レーン（左/中左/中右/右）に散らす。
        let formation: [(x: Float, z: Float, role: PlayerRole)] = [
            (0,        L / 2 - 1.0, .keeper),      // GK
            (-W * 0.30, L * 0.30,   .defender),    // 左サイドバック
            ( W * 0.30, L * 0.30,   .defender),    // 右サイドバック
            (-W * 0.26, L * 0.10,   .midfielder),  // 左ウイング
            ( W * 0.26, L * 0.06,   .forward),     // 右前
        ]
        var id = 0
        for (x, z, role) in formation {
            // home は +z 自陣 → 配置はそのまま。away はミラー。
            let home = SIMD2<Float>(x, z)
            players.append(PlayerState(id: id, side: .home, isKeeper: role == .keeper, role: role, pos: home, homePos: home))
            id += 1
        }
        for (x, z, role) in formation {
            let away = SIMD2<Float>(-x, -z)
            players.append(PlayerState(id: id, side: .away, isKeeper: role == .keeper, role: role, pos: away, homePos: away))
            id += 1
        }
        ball = BallState()
        kickoffCooldown = 0.4
        possessing = kickoffSide
        intentions.removeAll()   // キックオフで意図はリセット（AI が再供給）
        lastOutcome = nil
        updateControlledPlayer()
    }

    // MARK: - Tick

    public func tick(dt: Float) {
        lastOutcome = nil
        homeShotChanceReady = false
        incomingShotOnGoal = false
        notableDribble = nil
        tacticSuccess = nil
        if kickoffCooldown > 0 { kickoffCooldown -= dt }
        if kickCooldown > 0 { kickCooldown -= dt }

        stepBall(dt: dt)
        updatePossession(dt: dt)
        stepPlayers(dt: dt)
        updateControlledPlayer()
        resolvePossession(dt: dt)
        detectIncomingShot()
        checkGoals()
    }

    /// 保持権の更新。相手が「明確に」近い(0.4m差)＆支配圏内のときだけ奪取が成立する。
    /// 併せて AI の采配的中（マーク奪取／パス成功）を検知する。
    private func updatePossession(dt: Float) {
        let ballXZ = SIMD2<Float>(ball.pos.x, ball.pos.z)
        let dh = distanceToBall(of: .home, ballXZ: ballXZ)
        let da = distanceToBall(of: .away, ballXZ: ballXZ)
        let prev = possessing
        switch possessing {
        case .home:
            if da < dh - 0.4 && da < controlRadius { possessing = .away }
        case .away:
            if dh < da - 0.4 && dh < controlRadius { possessing = .home }
        }

        // 奪取：保持権が移った瞬間、奪った側の最寄り選手が mark 意図なら采配的中。
        if possessing != prev {
            let cid = closestFieldPlayerID(of: possessing, to: ballXZ)
            if intentions[cid]?.action == .mark { tacticSuccess = possessing }
            pendingPass = nil
        }

        // パス成功：宛先選手が支配圏内でボールを収めたら采配的中。
        if let pp = pendingPass {
            let cid = closestFieldPlayerID(of: pp.side, to: ballXZ)
            if possessing == pp.side, cid == pp.to,
               distanceToBall(of: pp.side, ballXZ: ballXZ) < controlRadius {
                tacticSuccess = pp.side
                pendingPass = nil
            } else {
                pendingPass?.ttl -= dt
                if (pendingPass?.ttl ?? 0) <= 0 { pendingPass = nil }
            }
        }
    }

    private func distanceToBall(of side: TeamSide, ballXZ: SIMD2<Float>) -> Float {
        var best = Float.greatestFiniteMagnitude
        for p in players where p.side == side && !p.isKeeper {
            best = min(best, simd_length(p.pos - ballXZ))
        }
        return best
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

    /// マルチエージェント AI：ポゼッション → ロール別の行き先 → ステアリング(分離)で移動。
    private func stepPlayers(dt: Float) {
        let ballXZ = SIMD2<Float>(ball.pos.x, ball.pos.z)
        let attackingSide = possessing
        // 各チームでボールに最も近い「プレッサー（ボールに行く1人）」。
        let homePresser = closestFieldPlayerID(of: .home, to: ballXZ)
        let awayPresser = closestFieldPlayerID(of: .away, to: ballXZ)

        for i in players.indices {
            var p = players[i]
            var target: SIMD2<Float>
            var speed = playerSpeed

            if p.isKeeper {
                let gx = simd_clamp(ball.pos.x, -Pitch.goalWidth / 2, Pitch.goalWidth / 2)
                target = SIMD2(gx, p.homePos.y)
                speed = keeperSpeed
            } else if let intent = intentions[p.id] {
                // AI エージェントの意図を実行。ボールを扱う系はボールへ寄る。
                switch intent.action {
                case .shoot, .dribble, .pass:
                    target = ballXZ
                case .move, .mark, .support, .hold:
                    target = intent.target
                }
            } else {
                let presserID = (p.side == .home) ? homePresser : awayPresser
                if p.id == presserID {
                    target = ballXZ                       // ボールへ直行（追う/奪う）
                } else if p.side == attackingSide {
                    target = attackTarget(for: p, ballXZ: ballXZ)
                } else {
                    target = defendTarget(for: p, ballXZ: ballXZ)
                }
            }

            // ステアリング：目標へ向かう力 ＋ 味方から離れる分離力。
            var steer = target - p.pos
            let d = simd_length(steer)
            steer = d > 0.001 ? steer / d : .zero
            let sep = separation(for: p)
            var dir = steer + sep * 1.4
            let dl = simd_length(dir)
            dir = dl > 0.001 ? dir / dl : .zero

            // arrive：目標に近いほど減速（プレッサーは緩めない）。
            let isPresser = !p.isKeeper && p.id == ((p.side == .home) ? homePresser : awayPresser)
            let arrive: Float = (!isPresser && d < 1.2) ? max(0.0, d / 1.2) : 1
            p.vel = dir * speed * arrive

            p.pos += p.vel * dt
            p.pos.x = simd_clamp(p.pos.x, -Pitch.width / 2, Pitch.width / 2)
            p.pos.y = simd_clamp(p.pos.y, -Pitch.length / 2, Pitch.length / 2)
            players[i] = p
        }
    }

    // MARK: - エージェントの行き先計算

    /// 攻撃時：ボールを起点に、ロールごとの深さ＋幅でスペースに開く（パスの受け手作り）。
    private func attackTarget(for p: PlayerState, ballXZ: SIMD2<Float>) -> SIMD2<Float> {
        let forwardZ: Float = p.side == .home ? -1 : 1
        let depth: Float
        switch p.role {
        case .forward:    depth = 9     // 前線へ走り込む（裏抜け）
        case .midfielder: depth = 2     // ボール周辺をサポート
        default:          depth = -6    // DF は後方で安全確保
        }
        var z = ballXZ.y + forwardZ * depth
        z = simd_clamp(z, -Pitch.length / 2 + 2, Pitch.length / 2 - 2)
        // レーン保持を優先（ボール寄せは弱め 0.2）＋攻撃時はやや外へストレッチして幅を使う。
        let lane = simd_clamp(p.homePos.x * 1.15, -Pitch.width / 2 + 1, Pitch.width / 2 - 1)
        let x = simd_mix(lane, ballXZ.x, 0.2)
        return SIMD2(x, z)
    }

    /// 守備時：ゴール側に立つ。DF は最寄りの敵をマーク、他はブロックを作る。
    private func defendTarget(for p: PlayerState, ballXZ: SIMD2<Float>) -> SIMD2<Float> {
        let ownGoal = SIMD2<Float>(0, p.side.defendingGoalZ)
        if p.role == .defender, let opp = nearestOpponent(to: p) {
            // 相手とゴールの間（ゴール側）に立って通させない。
            let toGoal = ownGoal - opp.pos
            let dir = simd_length(toGoal) > 0 ? simd_normalize(toGoal) : SIMD2(0, 0)
            return opp.pos + dir * 2.5
        }
        // MF/FW はボールと自ゴールの中間でブロックを形成（レーン幅を保持）。
        let z = simd_mix(ballXZ.y, p.side.defendingGoalZ, 0.4)
        let x = simd_mix(p.homePos.x, ballXZ.x, 0.28)
        return SIMD2(x, z)
    }

    /// 近すぎる味方から離れる分離ベクトル（団子防止）。
    private func separation(for p: PlayerState) -> SIMD2<Float> {
        let radius: Float = 4.0
        var v = SIMD2<Float>.zero
        for o in players where o.side == p.side && o.id != p.id {
            let diff = p.pos - o.pos
            let dist = simd_length(diff)
            if dist > 0.001 && dist < radius {
                v += (diff / dist) * (1 - dist / radius)
            }
        }
        return v
    }

    /// 指定チームでボールに最も近い非 GK の id。
    private func closestFieldPlayerID(of side: TeamSide, to ball: SIMD2<Float>) -> Int {
        var best = Float.greatestFiniteMagnitude
        var id = -1
        for p in players where p.side == side && !p.isKeeper {
            let d = simd_length(p.pos - ball)
            if d < best { best = d; id = p.id }
        }
        return id
    }

    /// p から最も近い相手の非 GK。
    private func nearestOpponent(to p: PlayerState) -> PlayerState? {
        var best = Float.greatestFiniteMagnitude
        var opp: PlayerState?
        for o in players where o.side != p.side && !o.isKeeper {
            let d = simd_length(o.pos - p.pos)
            if d < best { best = d; opp = o }
        }
        return opp
    }

    /// from→to のパス線上に相手がいなければ true（コースが空いている）。
    private func isLaneOpen(from: SIMD2<Float>, to: SIMD2<Float>, side: TeamSide) -> Bool {
        let seg = to - from
        let len = simd_length(seg)
        guard len > 0.001 else { return true }
        let dir = seg / len
        for o in players where o.side != side {
            let rel = o.pos - from
            let proj = simd_dot(rel, dir)
            guard proj > 0.5 && proj < len else { continue }    // 区間内のみ
            let perp = simd_length(rel - dir * proj)
            if perp < 1.6 { return false }                       // 線の近くに敵
        }
        return true
    }

    /// ボール保持者の AI 判断（シュート/パス/ドリブル）と人間チャンスの検知。
    private func resolvePossession(dt: Float) {
        guard kickoffCooldown <= 0 else { return }
        let ballXZ = SIMD2<Float>(ball.pos.x, ball.pos.z)

        // 保持チームのボールに最も近い選手が支配圏内ならボールを扱える。
        let carrierID = closestFieldPlayerID(of: possessing, to: ballXZ)
        let carrier = players.first { $0.id == carrierID && simd_length($0.pos - ballXZ) < controlRadius }

        if let c = carrier {
            let goal = SIMD2<Float>(0, c.side.attackingGoalZ)
            let goalDist = simd_length(goal - c.pos)
            // ボールが「足元で収まっている」か（接地＋低速＋至近）。
            let ballSpeed = simd_length(SIMD2(ball.vel.x, ball.vel.z))
            let settled = ball.pos.y < 0.5 && ballSpeed < 9
                && simd_length(c.pos - ballXZ) < controlRadius * 0.85

            // home がゴール圏内で「ボールを足元に収めている」時だけ人間のシュートチャンス。
            if c.side == .home && goalDist < shootRange {
                if settled { homeShotChanceReady = true }   // 収まっていなければ待つ
            } else if kickCooldown <= 0 {
                if let intent = intentions[c.id], applyCarrierIntention(intent, carrier: c, goalDist: goalDist) {
                    // AI の意図どおりに処理した
                } else {
                    aiAct(carrier: c, goalDist: goalDist)
                }
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

    /// 保持者が AI の意図どおりにボールを処理。処理したら true。
    private func applyCarrierIntention(_ intent: Intention, carrier c: PlayerState, goalDist: Float) -> Bool {
        switch intent.action {
        case .shoot:
            let targetX = (rand() - 0.5) * Pitch.goalWidth * 0.8
            shoot(from: c.pos, to: SIMD2(targetX, c.side.attackingGoalZ), power: 0.85 + rand() * 0.15, loft: 0.1)
            kickCooldown = 0.5
            if c.pos.y * (c.side == .home ? -1 : 1) > 0 { notableDribble = nil }
            return true
        case .pass:
            if let toID = intent.passTo, let mate = players.first(where: { $0.id == toID }) {
                let d = simd_length(mate.pos - c.pos)
                shoot(from: c.pos, to: mate.pos, power: simd_clamp(d / 22, 0.35, 0.7), loft: 0.08)
                kickCooldown = 0.35
                pendingPass = (to: toID, side: c.side, ttl: 2.5)   // 成功判定を開始
                return true
            }
            return false
        case .dribble:
            let forwardZ: Float = c.side == .home ? -1 : 1
            shoot(from: c.pos, to: c.pos + SIMD2(0, forwardZ * 6), power: 0.42, loft: 0)
            kickCooldown = 0.4
            if (c.pos.y * forwardZ) > 0 { notableDribble = c.side }
            return true
        default:
            return false   // move/mark/support/hold はボール処理しない → 既定 AI へ
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
            // ドリブル：ゴール方向へ運ぶ（連続タッチ）。保持権があるので運び切れる。
            shoot(from: c.pos, to: c.pos + SIMD2(0, forwardZ * 6), power: 0.42, loft: 0)
            kickCooldown = 0.4
            // 相手陣でのドリブルは「良いシーン」としてカットイン対象に。
            let inAttackingHalf = (c.pos.y * forwardZ) > 0
            if inAttackingHalf { notableDribble = c.side }
        }
    }

    /// 前方にいて射程内・**パスコースが空いている**最も進んだ味方を返す。
    private func bestPassTarget(for c: PlayerState, forwardZ: Float) -> PlayerState? {
        var bestMate: PlayerState?
        var bestAdvance: Float = 2  // 最低 2m は前進している相手のみ
        for m in players where m.side == c.side && !m.isKeeper && m.id != c.id {
            let advance = (m.pos.y - c.pos.y) * forwardZ   // 攻める方向への前進量
            let dist = simd_length(m.pos - c.pos)
            guard advance > bestAdvance, dist < 20 else { continue }
            guard isLaneOpen(from: c.pos, to: m.pos, side: c.side) else { continue }  // 敵がコースにいたら避ける
            bestAdvance = advance
            bestMate = m
        }
        return bestMate
    }

    /// away の枠内シュートが home ゴール「間近」へ迫っているかを判定（守備チャンス用）。
    /// ゴール前 14m 以内・0.8 秒以内に到達・枠内、のときだけ発動して
    /// 「ボールが遠いのにピンチ」を防ぐ。
    private func detectIncomingShot() {
        guard ball.vel.z > 8 else { return }
        // ゴール前 14m 以内（ownGoalZ は +z 側）。
        guard ball.pos.z > Pitch.ownGoalZ - 14 else { return }
        let t = (Pitch.ownGoalZ - ball.pos.z) / max(ball.vel.z, 0.001)
        guard t > 0, t < 0.8 else { return }
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
}
