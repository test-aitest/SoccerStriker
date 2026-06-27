// GameModel.swift の移植：試合のオーケストレーション層。
//   - SoccerEngine を可変 dt で回す（両チーム AI 自動進行）
//   - 各フレームの状態を render 用ペイロードに整形する
//   - 要所で「人間のチャンス」を割り込ませる（攻撃=シュート / 守備=セーブ）
//     ゲージはチャンスごとに「タイミング」と「連打パワー」が交互。
// Web 版は Gemini を使わず、エンジン内蔵のルールベース AI で進行する。

import { SoccerEngine, Side } from './engine.js';
import { length } from './vec.js';
import { poseURL } from './countries.js';

export const Phase = { play: 'play', chance: 'chance' };

export class Game {
  constructor(home, away, audio) {
    this.engine = new SoccerEngine();
    this.home = home;
    this.away = away;
    this.audio = audio;

    this.homeScore = 0;
    this.awayScore = 0;
    this.lastEventLabel = '';
    this.phase = Phase.play;
    this.chance = null;
    this.aiActive = false; // Web 版は常にルールAI

    this.cutIn = null;
    this.cutInTimeLeft = 0;
    this.cutInSeq = 0;
    this.dribbleCutInCooldown = 0;
    this.managerCutInCooldown = 0;

    this.pendingKick = null;
    this.triggerCooldown = 1.0;
    this.chanceCounter = 0;
    this.prevHome = 0;
    this.prevAway = 0;
  }

  start() {
    this.engine.resetFormation(Side.home);
    this.prevHome = 0;
    this.prevAway = 0;
    this.audio?.start();
    this.audio?.startAmbient();
    this.audio?.whistle(); // キックオフ
  }

  // 「振り」イベント（キーボード連打/押下）。チャンス中のみ消費される。
  registerKick() {
    this.pendingKick = { kind: 'shoot', power: 0.9, aim: 0, loft: 0.1 };
  }

  // MARK: - Loop
  tick(dt) {
    dt = Math.min(Math.max(dt, 0), 1 / 20);
    this._updateCutIn(dt);

    if (this.phase === Phase.play) {
      this.pendingKick = null; // チャンス外の振りは無視
      const beforeSpeed = length3(this.engine.ball.vel);
      this.engine.tick(dt);
      const afterSpeed = length3(this.engine.ball.vel);
      if (afterSpeed - beforeSpeed > 5) this.audio?.kick();
      this._syncScore();
      this._forwardOutcome(this.engine.lastOutcome);

      if (this.dribbleCutInCooldown > 0) this.dribbleCutInCooldown -= dt;
      if (this.engine.notableDribble && this.dribbleCutInCooldown <= 0) {
        const side = this.engine.notableDribble;
        const c = side === Side.home ? this.home : this.away;
        this._showCutIn(poseURL(c, 'dribble'), 'NICE DRIBBLE!', c.primaryHex, side === Side.home);
        this.dribbleCutInCooldown = 6;
      }
      if (this.managerCutInCooldown > 0) this.managerCutInCooldown -= dt;
      if (this.engine.tacticSuccess && this.managerCutInCooldown <= 0) {
        this._managerCutIn(this.engine.tacticSuccess);
      }
      if (this.triggerCooldown > 0) this.triggerCooldown -= dt;
      else this._detectChance();
    } else {
      this._updateChance(dt);
    }
    this._reactToScore();
  }

  _updateCutIn(dt) {
    if (!this.cutIn) return;
    this.cutInTimeLeft -= dt;
    if (this.cutInTimeLeft <= 0) this.cutIn = null;
  }

  _showCutIn(image, title, colorHex, fromLeft, isManager = false) {
    this.cutInSeq += 1;
    this.cutIn = { id: this.cutInSeq, image, title, color: colorHex, fromLeft, isManager };
    this.cutInTimeLeft = isManager ? 2.0 : 1.7;
  }

  _reactToScore() {
    if (this.homeScore > this.prevHome) { this.audio?.goal(); this.prevHome = this.homeScore; this._managerCutIn(Side.home); }
    if (this.awayScore > this.prevAway) { this.audio?.conceded(); this.prevAway = this.awayScore; this._managerCutIn(Side.away); }
  }

  _managerCutIn(side) {
    const c = side === Side.home ? this.home : this.away;
    const lines = ['TACTICS ON POINT!', 'JUST AS PLANNED!', 'GREAT CALL!', 'GOTCHA!'];
    const text = lines[this.cutInSeq % lines.length];
    this._showCutIn(poseURL(c, 'director'), text, c.primaryHex, side === Side.home, true);
    this.managerCutInCooldown = 5;
  }

  _syncScore() {
    this.homeScore = this.engine.homeScore;
    this.awayScore = this.engine.awayScore;
  }

  _forwardOutcome(outcome) {
    if (outcome === 'miss') this.lastEventLabel = 'MISS';
  }

  // MARK: - Chance
  _detectChance() {
    if (this.engine.homeShotChanceReady) this._startChance('shot');
    else if (this.engine.incomingShotOnGoal) this._startChance('save');
  }

  _startChance(kind) {
    this.chanceCounter += 1;
    const gauge = this.chanceCounter % 2 === 0 ? 'power' : 'timing';
    this.chance = {
      kind, gauge,
      progress: 0, markerDir: 1, charge: 0,
      sweetLo: 0.4, sweetHi: 0.6,
      timeLeft: gauge === 'power' ? 2.6 : 2.2,
      flash: 0, resolved: false, success: null, resultHold: 0,
    };
    this.phase = Phase.chance;
    this.pendingKick = null;
    this.lastEventLabel = '';
    this.audio?.chanceCue();
    if (kind === 'shot') {
      this._showCutIn(poseURL(this.home, 'shoot'), 'SHOOT!', this.home.primaryHex, true);
    } else {
      this._showCutIn(poseURL(this.away, 'shoot'), 'DANGER!', this.away.primaryHex, false);
    }
  }

  _updateChance(dt) {
    const c = this.chance;
    if (!c) { this.phase = Phase.play; return; }

    if (c.resolved) {
      c.resultHold -= dt;
      if (c.resultHold <= 0) this._finishChance();
      return;
    }

    c.timeLeft -= dt;
    if (c.flash > 0) c.flash -= dt;

    if (c.gauge === 'timing') {
      const sweep = 1.25;
      c.progress += c.markerDir * sweep * dt;
      if (c.progress >= 1) { c.progress = 1; c.markerDir = -1; }
      if (c.progress <= 0) { c.progress = 0; c.markerDir = 1; }
    } else {
      c.charge = Math.max(0, c.charge - 0.14 * dt);
    }

    if (this.pendingKick != null) {
      this.pendingKick = null;
      if (c.gauge === 'timing') {
        const ok = c.progress >= c.sweetLo && c.progress <= c.sweetHi;
        this._resolve(c, ok);
      } else {
        c.charge = Math.min(1, c.charge + 0.17);
        c.flash = 0.16;
        if (c.charge >= 1) this._resolve(c, true);
      }
    }

    if (!c.resolved && c.timeLeft <= 0) {
      if (c.gauge === 'power') this._resolve(c, c.charge >= 0.7);
      else this._resolve(c, false);
    }
  }

  _resolve(c, success) {
    c.resolved = true;
    c.success = success;
    c.resultHold = 1.1;

    if (c.kind === 'shot') {
      if (success) {
        this.engine.awardGoal(Side.home);
        this.lastEventLabel = 'GREAT SHOT! GOAL!!';
      } else {
        this.engine.clearBall(1);
        this.lastEventLabel = 'SHOT MISSED…';
      }
    } else { // save
      if (success) {
        this.engine.clearBall(-1);
        this.lastEventLabel = 'GREAT SAVE!';
        this.audio?.save();
      } else {
        this.engine.awardGoal(Side.away);
        this.lastEventLabel = 'CONCEDED…';
      }
    }
    this._syncScore();
  }

  _finishChance() {
    this.chance = null;
    this.phase = Phase.play;
    this.triggerCooldown = 1.6;
    this.lastEventLabel = '';
  }

  // MARK: - Render payload
  renderState() {
    const b = this.engine.ball;
    const players = this.engine.players.map((p) => ({
      id: p.id,
      side: p.side,
      keeper: p.isKeeper,
      x: p.pos.x,
      z: p.pos.z,
      ctrl: p.id === this.engine.controlledPlayerID,
    }));
    return {
      ball: { x: b.pos.x, y: b.pos.y, z: b.pos.z },
      players,
      home: this.engine.homeScore,
      away: this.engine.awayScore,
      homeShirt: this.home.primaryHex,
      homeShorts: this.home.secondaryHex,
      awayShirt: this.away.primaryHex,
      awayShorts: this.away.secondaryHex,
    };
  }
}

// チャンスゲージのタイトル文（MatchView.Chance.title 相当）。
export function chanceTitle(c) {
  if (c.kind === 'shot' && c.gauge === 'timing') return 'SHOOT! Swing in the zone';
  if (c.kind === 'shot' && c.gauge === 'power') return 'SHOOT! Mash to charge power';
  if (c.kind === 'save' && c.gauge === 'timing') return 'DANGER! Swing in the zone to save';
  return 'DANGER! Mash to block';
}

const length3 = (v) => Math.hypot(v.x, v.y, v.z);
