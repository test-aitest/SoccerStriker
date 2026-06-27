// SoccerEngine.swift の移植：4vs4 サッカーの最小シミュレーション。
//   - tick(dt) で物理 + ルールベース AI を 1 ステップ進める
//   - applyKick(kick) で「操作中の選手」に蹴りを適用する
//   - players / ball / score をそのまま描画レイヤーへ渡す
// 座標：選手 pos={x,z}（ピッチ平面）、ボール pos/vel={x,y,z}（y=高さ）。

import { Pitch, BallPhysics } from './constants.js';
import { v2, add, sub, scale, dot, length, normalize, clamp, mix } from './vec.js';

// チーム陣営。home がプレイヤー側（-z のゴールを攻める）。
export const Side = { home: 'home', away: 'away' };
const attackingGoalZ = (side) => (side === Side.home ? Pitch.enemyGoalZ : Pitch.ownGoalZ);
const defendingGoalZ = (side) => (side === Side.home ? Pitch.ownGoalZ : Pitch.enemyGoalZ);

// 選手の役割。
export const Role = { keeper: 'keeper', defender: 'defender', midfielder: 'midfielder', forward: 'forward' };

export class SoccerEngine {
  constructor() {
    this.ball = { pos: { x: 0, y: BallPhysics.radius, z: 0 }, vel: { x: 0, y: 0, z: 0 } };
    this.players = [];
    this.homeScore = 0;
    this.awayScore = 0;
    this.lastOutcome = null; // 'goal' | 'conceded' | 'save' | 'touch' | 'miss'
    this.controlledPlayerID = 0;

    this.controlRadius = 1.2;
    this.playerSpeed = 6.5;
    this.keeperSpeed = 4.5;
    this.shootRange = 13;
    this.kickoffCooldown = 0;
    this.kickCooldown = 0;
    this.rngState = 0x9e3779b9 >>> 0; // xorshift32（決定論）
    this.possessing = Side.home;

    this.intentions = new Map(); // playerID -> Intention（AI 任意供給。未使用ならルールAI）
    this.aiControlled = false;

    // GameModel が監視するチャンス/演出フラグ。
    this.homeShotChanceReady = false;
    this.incomingShotOnGoal = false;
    this.notableDribble = null; // Side | null
    this.tacticSuccess = null; // Side | null

    this.pendingPass = null; // { to, side, ttl }

    this.resetFormation(Side.home);
  }

  setIntentions(list) {
    if (!list || list.length === 0) return;
    for (const it of list) this.intentions.set(it.playerID, it);
    this.aiControlled = true;
  }

  // MARK: - Setup
  resetFormation(kickoffSide) {
    this.players = [];
    // 4-4 のシンプルな配置（GK + DF2 + MF1 + FW1）。
    const formation = [
      { x: 0, z: Pitch.length / 2 - 1.0, role: Role.keeper },
      { x: -Pitch.width / 4, z: Pitch.length / 4, role: Role.defender },
      { x: Pitch.width / 4, z: Pitch.length / 4, role: Role.defender },
      { x: 0, z: Pitch.length / 8, role: Role.midfielder },
      { x: 0, z: 1.5, role: Role.forward },
    ];
    let id = 0;
    for (const f of formation) {
      const home = v2(f.x, f.z);
      this.players.push(this._mkPlayer(id++, Side.home, f.role === Role.keeper, f.role, home));
    }
    for (const f of formation) {
      const away = v2(-f.x, -f.z);
      this.players.push(this._mkPlayer(id++, Side.away, f.role === Role.keeper, f.role, away));
    }
    this.ball = { pos: { x: 0, y: BallPhysics.radius, z: 0 }, vel: { x: 0, y: 0, z: 0 } };
    this.kickoffCooldown = 0.4;
    this.possessing = kickoffSide;
    this.intentions.clear();
    this.lastOutcome = null;
    this._updateControlledPlayer();
  }

  _mkPlayer(id, side, isKeeper, role, pos) {
    return {
      id, side, isKeeper, role,
      pos: { x: pos.x, z: pos.z },
      homePos: { x: pos.x, z: pos.z },
      vel: { x: 0, z: 0 },
    };
  }

  // MARK: - Tick
  tick(dt) {
    this.lastOutcome = null;
    this.homeShotChanceReady = false;
    this.incomingShotOnGoal = false;
    this.notableDribble = null;
    this.tacticSuccess = null;
    if (this.kickoffCooldown > 0) this.kickoffCooldown -= dt;
    if (this.kickCooldown > 0) this.kickCooldown -= dt;

    this._stepBall(dt);
    this._updatePossession(dt);
    this._stepPlayers(dt);
    this._updateControlledPlayer();
    this._resolvePossession(dt);
    this._detectIncomingShot();
    this._checkGoals();
  }

  _updatePossession(dt) {
    const ballXZ = v2(this.ball.pos.x, this.ball.pos.z);
    const dh = this._distanceToBall(Side.home, ballXZ);
    const da = this._distanceToBall(Side.away, ballXZ);
    const prev = this.possessing;
    if (this.possessing === Side.home) {
      if (da < dh - 0.4 && da < this.controlRadius) this.possessing = Side.away;
    } else {
      if (dh < da - 0.4 && dh < this.controlRadius) this.possessing = Side.home;
    }

    if (this.possessing !== prev) {
      const cid = this._closestFieldPlayerID(this.possessing, ballXZ);
      if (this.intentions.get(cid)?.action === 'mark') this.tacticSuccess = this.possessing;
      this.pendingPass = null;
    }

    if (this.pendingPass) {
      const pp = this.pendingPass;
      const cid = this._closestFieldPlayerID(pp.side, ballXZ);
      if (this.possessing === pp.side && cid === pp.to &&
          this._distanceToBall(pp.side, ballXZ) < this.controlRadius) {
        this.tacticSuccess = pp.side;
        this.pendingPass = null;
      } else {
        pp.ttl -= dt;
        if (pp.ttl <= 0) this.pendingPass = null;
      }
    }
  }

  _distanceToBall(side, ballXZ) {
    let best = Infinity;
    for (const p of this.players) {
      if (p.side === side && !p.isKeeper) best = Math.min(best, length(sub(p.pos, ballXZ)));
    }
    return best;
  }

  _stepBall(dt) {
    const b = this.ball;
    b.vel.y -= BallPhysics.gravity * dt;
    b.pos.x += b.vel.x * dt;
    b.pos.y += b.vel.y * dt;
    b.pos.z += b.vel.z * dt;
    // 地面バウンド
    if (b.pos.y < BallPhysics.radius) {
      b.pos.y = BallPhysics.radius;
      if (b.vel.y < 0) b.vel.y = -b.vel.y * BallPhysics.restitution;
      const damp = Math.max(0, 1 - BallPhysics.groundDamping * dt);
      b.vel.x *= damp;
      b.vel.z *= damp;
      if (Math.abs(b.vel.y) < 0.4) b.vel.y = 0;
    }
    // サイドライン反射（簡易）
    const halfW = Pitch.width / 2;
    if (Math.abs(b.pos.x) > halfW) {
      b.pos.x = clamp(b.pos.x, -halfW, halfW);
      b.vel.x = -b.vel.x * 0.5;
    }
  }

  _stepPlayers(dt) {
    const ballXZ = v2(this.ball.pos.x, this.ball.pos.z);
    const attackingSide = this.possessing;
    const homePresser = this._closestFieldPlayerID(Side.home, ballXZ);
    const awayPresser = this._closestFieldPlayerID(Side.away, ballXZ);

    for (const p of this.players) {
      let target;
      let speed = this.playerSpeed;

      if (p.isKeeper) {
        const gx = clamp(this.ball.pos.x, -Pitch.goalWidth / 2, Pitch.goalWidth / 2);
        target = v2(gx, p.homePos.z);
        speed = this.keeperSpeed;
      } else if (this.intentions.has(p.id)) {
        const intent = this.intentions.get(p.id);
        switch (intent.action) {
          case 'shoot': case 'dribble': case 'pass':
            target = ballXZ; break;
          default: // move/mark/support/hold
            target = v2(intent.targetX, intent.targetZ); break;
        }
      } else {
        const presserID = p.side === Side.home ? homePresser : awayPresser;
        if (p.id === presserID) target = ballXZ;
        else if (p.side === attackingSide) target = this._attackTarget(p, ballXZ);
        else target = this._defendTarget(p, ballXZ);
      }

      // ステアリング：目標へ向かう力 + 味方から離れる分離力。
      let steer = sub(target, p.pos);
      const d = length(steer);
      steer = d > 0.001 ? scale(steer, 1 / d) : v2();
      const sep = this._separation(p);
      let dir = add(steer, scale(sep, 1.4));
      const dl = length(dir);
      dir = dl > 0.001 ? scale(dir, 1 / dl) : v2();

      const isPresser = !p.isKeeper && p.id === (p.side === Side.home ? homePresser : awayPresser);
      const arrive = (!isPresser && d < 1.2) ? Math.max(0, d / 1.2) : 1;
      p.vel = scale(dir, speed * arrive);

      p.pos.x += p.vel.x * dt;
      p.pos.z += p.vel.z * dt;
      p.pos.x = clamp(p.pos.x, -Pitch.width / 2, Pitch.width / 2);
      p.pos.z = clamp(p.pos.z, -Pitch.length / 2, Pitch.length / 2);
    }
  }

  // MARK: - エージェントの行き先計算
  _attackTarget(p, ballXZ) {
    const forwardZ = p.side === Side.home ? -1 : 1;
    let depth;
    switch (p.role) {
      case Role.forward: depth = 9; break;
      case Role.midfielder: depth = 2; break;
      default: depth = -6; break;
    }
    let z = ballXZ.z + forwardZ * depth;
    z = clamp(z, -Pitch.length / 2 + 2, Pitch.length / 2 - 2);
    const x = mix(p.homePos.x, ballXZ.x, 0.3);
    return v2(x, z);
  }

  _defendTarget(p, ballXZ) {
    const ownGoal = v2(0, defendingGoalZ(p.side));
    if (p.role === Role.defender) {
      const opp = this._nearestOpponent(p);
      if (opp) {
        const toGoal = sub(ownGoal, opp.pos);
        const dir = length(toGoal) > 0 ? normalize(toGoal) : v2(0, 0);
        return add(opp.pos, scale(dir, 2.5));
      }
    }
    const z = mix(ballXZ.z, defendingGoalZ(p.side), 0.4);
    const x = mix(p.homePos.x, ballXZ.x, 0.3);
    return v2(x, z);
  }

  _separation(p) {
    const radius = 3.5;
    let v = v2();
    for (const o of this.players) {
      if (o.side !== p.side || o.id === p.id) continue;
      const diff = sub(p.pos, o.pos);
      const dist = length(diff);
      if (dist > 0.001 && dist < radius) v = add(v, scale(diff, (1 - dist / radius) / dist));
    }
    return v;
  }

  _closestFieldPlayerID(side, ball) {
    let best = Infinity, id = -1;
    for (const p of this.players) {
      if (p.side === side && !p.isKeeper) {
        const d = length(sub(p.pos, ball));
        if (d < best) { best = d; id = p.id; }
      }
    }
    return id;
  }

  _nearestOpponent(p) {
    let best = Infinity, opp = null;
    for (const o of this.players) {
      if (o.side !== p.side && !o.isKeeper) {
        const d = length(sub(o.pos, p.pos));
        if (d < best) { best = d; opp = o; }
      }
    }
    return opp;
  }

  _isLaneOpen(from, to, side) {
    const seg = sub(to, from);
    const len = length(seg);
    if (len <= 0.001) return true;
    const dir = scale(seg, 1 / len);
    for (const o of this.players) {
      if (o.side === side) continue;
      const rel = sub(o.pos, from);
      const proj = dot(rel, dir);
      if (proj <= 0.5 || proj >= len) continue;
      const perp = length(sub(rel, scale(dir, proj)));
      if (perp < 1.6) return false;
    }
    return true;
  }

  _resolvePossession(dt) {
    if (this.kickoffCooldown > 0) return;
    const ballXZ = v2(this.ball.pos.x, this.ball.pos.z);

    const carrierID = this._closestFieldPlayerID(this.possessing, ballXZ);
    const carrier = this.players.find(
      (q) => q.id === carrierID && length(sub(q.pos, ballXZ)) < this.controlRadius
    );

    if (carrier) {
      const c = carrier;
      const goal = v2(0, attackingGoalZ(c.side));
      const goalDist = length(sub(goal, c.pos));
      const ballSpeed = length(v2(this.ball.vel.x, this.ball.vel.z));
      const settled = this.ball.pos.y < 0.5 && ballSpeed < 9 &&
        length(sub(c.pos, ballXZ)) < this.controlRadius * 0.85;

      if (c.side === Side.home && goalDist < this.shootRange) {
        if (settled) this.homeShotChanceReady = true;
      } else if (this.kickCooldown <= 0) {
        const intent = this.intentions.get(c.id);
        if (intent && this._applyCarrierIntention(intent, c, goalDist)) {
          // AI の意図どおりに処理した
        } else {
          this._aiAct(c, goalDist);
        }
      }
    }

    // away GK のみ自動クリア（home ゴールは人間がセーブ）。
    for (const p of this.players) {
      if (p.isKeeper && p.side === Side.away && length(sub(p.pos, ballXZ)) < this.controlRadius + 0.4) {
        this._autoKick(v2(0, 1), 0.7, 0.3);
        this.lastOutcome = 'save';
      }
    }
  }

  _applyCarrierIntention(intent, c, goalDist) {
    switch (intent.action) {
      case 'shoot': {
        const targetX = (this._rand() - 0.5) * Pitch.goalWidth * 0.8;
        this._shoot(c.pos, v2(targetX, attackingGoalZ(c.side)), 0.85 + this._rand() * 0.15, 0.1);
        this.kickCooldown = 0.5;
        return true;
      }
      case 'pass': {
        if (intent.passTo != null) {
          const mate = this.players.find((q) => q.id === intent.passTo);
          if (mate) {
            const d = length(sub(mate.pos, c.pos));
            this._shoot(c.pos, mate.pos, clamp(d / 22, 0.35, 0.7), 0.08);
            this.kickCooldown = 0.35;
            this.pendingPass = { to: intent.passTo, side: c.side, ttl: 2.5 };
            return true;
          }
        }
        return false;
      }
      case 'dribble': {
        const forwardZ = c.side === Side.home ? -1 : 1;
        this._shoot(c.pos, add(c.pos, v2(0, forwardZ * 6)), 0.42, 0);
        this.kickCooldown = 0.4;
        if (c.pos.z * forwardZ > 0) this.notableDribble = c.side;
        return true;
      }
      default:
        return false;
    }
  }

  _aiAct(c, goalDist) {
    const forwardZ = c.side === Side.home ? -1 : 1;
    if (goalDist < this.shootRange) {
      const targetX = (this._rand() - 0.5) * Pitch.goalWidth * 0.8;
      this._shoot(c.pos, v2(targetX, attackingGoalZ(c.side)), 0.8 + this._rand() * 0.2, 0.1);
      this.kickCooldown = 0.5;
      return;
    }
    const mate = this._bestPassTarget(c, forwardZ);
    if (mate) {
      const d = length(sub(mate.pos, c.pos));
      this._shoot(c.pos, mate.pos, clamp(d / 22, 0.35, 0.7), 0.08);
      this.kickCooldown = 0.35;
    } else {
      this._shoot(c.pos, add(c.pos, v2(0, forwardZ * 6)), 0.42, 0);
      this.kickCooldown = 0.4;
      if (c.pos.z * forwardZ > 0) this.notableDribble = c.side;
    }
  }

  _bestPassTarget(c, forwardZ) {
    let bestMate = null;
    let bestAdvance = 2;
    for (const m of this.players) {
      if (m.side !== c.side || m.isKeeper || m.id === c.id) continue;
      const advance = (m.pos.z - c.pos.z) * forwardZ;
      const dist = length(sub(m.pos, c.pos));
      if (advance <= bestAdvance || dist >= 20) continue;
      if (!this._isLaneOpen(c.pos, m.pos, c.side)) continue;
      bestAdvance = advance;
      bestMate = m;
    }
    return bestMate;
  }

  _detectIncomingShot() {
    if (this.ball.vel.z <= 8) return;
    if (this.ball.pos.z <= Pitch.ownGoalZ - 14) return;
    const t = (Pitch.ownGoalZ - this.ball.pos.z) / Math.max(this.ball.vel.z, 0.001);
    if (t <= 0 || t >= 0.8) return;
    const xAtGoal = this.ball.pos.x + this.ball.vel.x * t;
    if (Math.abs(xAtGoal) < Pitch.goalWidth / 2 + 1) this.incomingShotOnGoal = true;
  }

  _shoot(from, to, power, loft) {
    let dir = sub(to, from);
    dir = length(dir) > 0 ? normalize(dir) : v2(0, -1);
    this._autoKick(dir, power, loft);
  }

  // 決定論的擬似乱数（xorshift32）。0…1。
  _rand() {
    let x = this.rngState >>> 0;
    x ^= (x << 13); x >>>= 0;
    x ^= (x >>> 17);
    x ^= (x << 5); x >>>= 0;
    this.rngState = x >>> 0;
    return (this.rngState % 100000) / 100000;
  }

  _autoKick(dir, power, loft) {
    const speed = BallPhysics.maxShotSpeed * power;
    this.ball.vel = { x: dir.x * speed, y: loft * speed * 0.6, z: dir.z * speed };
    this.ball.pos.y = Math.max(this.ball.pos.y, BallPhysics.radius);
  }

  _checkGoals() {
    const halfGoalW = Pitch.goalWidth / 2;
    const inWidth = Math.abs(this.ball.pos.x) < halfGoalW;
    const inHeight = this.ball.pos.y < Pitch.goalHeight;
    if (this.ball.pos.z < Pitch.enemyGoalZ && inWidth && inHeight) {
      this.homeScore += 1;
      this.lastOutcome = 'goal';
      this.resetFormation(Side.away);
    } else if (this.ball.pos.z > Pitch.ownGoalZ && inWidth && inHeight) {
      this.awayScore += 1;
      this.lastOutcome = 'conceded';
      this.resetFormation(Side.home);
    } else if ((this.ball.pos.z < Pitch.enemyGoalZ || this.ball.pos.z > Pitch.ownGoalZ) && !inWidth) {
      if (this.lastOutcome == null) this.lastOutcome = 'miss';
      const kickoff = this.ball.pos.z < 0 ? Side.home : Side.away;
      this.resetFormation(kickoff);
    }
  }

  // MARK: - Player kick（キーボード/iPhone の蹴り）
  applyKick(kick) {
    const p = this.players.find((q) => q.id === this.controlledPlayerID);
    if (!p) return false;
    const ballXZ = v2(this.ball.pos.x, this.ball.pos.z);
    if (length(sub(p.pos, ballXZ)) >= this.controlRadius + 0.5) return false;

    const forwardZ = p.side === Side.home ? -1 : 1;
    let dir = v2(kick.aim, forwardZ);
    dir = length(dir) > 0 ? normalize(dir) : v2(0, forwardZ);

    const power = Math.max(0.25, kick.power);
    let kindFactor;
    switch (kick.kind) {
      case 'dribble': kindFactor = 0.35; break;
      case 'divingHeader': kindFactor = 0.85; break;
      default: kindFactor = 1.0; break; // shoot
    }
    const speed = BallPhysics.maxShotSpeed * power * kindFactor;
    const loftV = kick.kind === 'divingHeader' ? -speed * 0.12 : kick.loft * speed * 0.7;

    this.ball.vel = { x: dir.x * speed, y: loftV, z: dir.z * speed };
    this.ball.pos.y = Math.max(this.ball.pos.y, BallPhysics.radius);
    this.lastOutcome = 'touch';
    return true;
  }

  // MARK: - Chance resolution（人間チャンスの結果適用）
  awardGoal(side) {
    if (side === Side.home) {
      this.homeScore += 1;
      this.lastOutcome = 'goal';
      this.resetFormation(Side.away);
    } else {
      this.awayScore += 1;
      this.lastOutcome = 'conceded';
      this.resetFormation(Side.home);
    }
  }

  clearBall(towardZ) {
    const speed = BallPhysics.maxShotSpeed * 0.55;
    this.ball.vel = { x: (this._rand() - 0.5) * 6, y: speed * 0.35, z: towardZ * speed };
    this.ball.pos.y = Math.max(this.ball.pos.y, BallPhysics.radius);
    this.kickCooldown = 0.7;
    this.lastOutcome = 'save';
  }

  // MARK: - Helpers
  _updateControlledPlayer() {
    const ballXZ = v2(this.ball.pos.x, this.ball.pos.z);
    let best = Infinity, bestID = this.controlledPlayerID;
    for (const p of this.players) {
      if (p.side === Side.home && !p.isKeeper) {
        const d = length(sub(p.pos, ballXZ));
        if (d < best) { best = d; bestID = p.id; }
      }
    }
    this.controlledPlayerID = bestID;
  }
}
