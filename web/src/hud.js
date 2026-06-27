// MatchView.swift の HUD 移植：スコアボード・チャンスゲージ・カットイン・結果表示。
// DOM オーバーレイとして構築し、update(game) で毎フレーム反映する。

import { flagImg } from './countries.js';
import { chanceTitle, Phase } from './game.js';

export class HUD {
  constructor(root, home, away) {
    this.root = root;
    this.home = home;
    this.away = away;
    root.innerHTML = '';
    root.className = 'hud';

    // --- スコアボード ---
    const sb = el('div', 'scoreboard');
    this.homeScoreEl = this._team(sb, home, 'home');
    sb.appendChild(el('span', 'vs', 'VS'));
    this.awayScoreEl = this._team(sb, away, 'away');
    const spacer = el('div', 'sb-spacer');
    sb.appendChild(spacer);
    sb.appendChild(el('div', 'badge', '🧠 Rule AI'));
    sb.appendChild(el('div', 'badge', '⌨︎ 連打 / Space'));
    root.appendChild(sb);

    // --- 中央メッセージ（結果ラベル）---
    this.centerMsg = el('div', 'center-msg');
    root.appendChild(this.centerMsg);

    // --- チャンスゲージ ---
    this.chanceEl = el('div', 'chance hidden');
    this.chanceTitleEl = el('div', 'chance-title');
    this.chanceResultEl = el('div', 'chance-result');
    this.chanceHintEl = el('div', 'chance-hint', 'Mash / Press  ↑ or Space');
    // timing
    this.timingWrap = el('div', 'gauge timing');
    this.timingZone = el('div', 'gauge-zone');
    this.timingMarker = el('div', 'gauge-marker');
    this.timingWrap.append(this.timingZone, this.timingMarker);
    // power
    this.powerWrap = el('div', 'gauge power');
    this.powerLine = el('div', 'gauge-line'); // 70% 成功ライン
    this.powerFill = el('div', 'gauge-fill');
    this.powerWrap.append(this.powerLine, this.powerFill);
    this.mashLabel = el('div', 'mash-label', 'MASH!');

    this.chanceEl.append(
      this.chanceTitleEl, this.chanceResultEl,
      this.timingWrap, this.powerWrap, this.mashLabel, this.chanceHintEl
    );
    root.appendChild(this.chanceEl);

    // --- カットイン ---
    this.cutInEl = el('div', 'cutin hidden');
    this.cutInImg = document.createElement('img');
    this.cutInImg.className = 'cutin-img';
    this.cutInBanner = el('div', 'cutin-banner');
    this.cutInEl.append(this.cutInImg, this.cutInBanner);
    root.appendChild(this.cutInEl);

    this._lastCutInId = -1;
  }

  _team(parent, country, side) {
    const wrap = el('div', `team ${side}`);
    wrap.appendChild(flagImg(country, 22));
    const col = el('div', 'team-col');
    const name = el('div', 'team-name', country.name);
    name.style.color = country.primaryHex;
    const score = el('div', 'team-score', '0');
    col.append(name, score);
    wrap.appendChild(col);
    parent.appendChild(wrap);
    return score;
  }

  update(game) {
    this.homeScoreEl.textContent = String(game.homeScore);
    this.awayScoreEl.textContent = String(game.awayScore);

    const c = game.chance;
    if (c) {
      this.chanceEl.classList.remove('hidden');
      this.chanceTitleEl.textContent = chanceTitle(c);
      this.chanceTitleEl.style.color = c.kind === 'save' ? '#ff5b5b' : '#ffe23b';

      if (c.success != null) {
        this.chanceResultEl.classList.remove('hidden');
        this.chanceResultEl.textContent = c.success ? 'SUCCESS!' : 'MISS';
        this.chanceResultEl.style.color = c.success ? '#46e07a' : 'rgba(255,255,255,0.8)';
        this._setGauge(null);
        this.chanceHintEl.style.visibility = 'hidden';
      } else {
        this.chanceResultEl.classList.add('hidden');
        this.chanceHintEl.style.visibility = 'visible';
        this._setGauge(c);
      }
    } else {
      this.chanceEl.classList.add('hidden');
    }

    // 結果ラベル（チャンスが無いときだけ中央に大きく出す）。
    if (!c && game.lastEventLabel) {
      this.centerMsg.textContent = game.lastEventLabel;
      this.centerMsg.classList.remove('hidden');
    } else {
      this.centerMsg.classList.add('hidden');
    }

    // カットイン
    this._updateCutIn(game.cutIn);
  }

  _setGauge(c) {
    if (!c) { this.timingWrap.style.display = 'none'; this.powerWrap.style.display = 'none'; this.mashLabel.style.display = 'none'; return; }
    if (c.gauge === 'timing') {
      this.timingWrap.style.display = 'block';
      this.powerWrap.style.display = 'none';
      this.mashLabel.style.display = 'none';
      this.timingZone.style.left = `${c.sweetLo * 100}%`;
      this.timingZone.style.width = `${(c.sweetHi - c.sweetLo) * 100}%`;
      this.timingMarker.style.left = `${c.progress * 100}%`;
    } else {
      this.timingWrap.style.display = 'none';
      this.powerWrap.style.display = 'block';
      this.mashLabel.style.display = 'block';
      this.powerLine.style.left = '70%';
      this.powerFill.style.width = `${Math.max(0, c.charge) * 100}%`;
      const flash = Math.min(1, c.flash * 6);
      this.powerFill.style.boxShadow = `0 0 ${12 + flash * 20}px rgba(255,150,0,${0.4 + flash * 0.6})`;
      this.mashLabel.style.transform = `scale(${1 + c.flash * 1.5})`;
    }
  }

  _updateCutIn(cut) {
    if (!cut) { this.cutInEl.classList.add('hidden'); this._lastCutInId = -1; return; }
    if (cut.id !== this._lastCutInId) {
      this._lastCutInId = cut.id;
      this.cutInEl.className = `cutin ${cut.fromLeft ? 'from-left' : 'from-right'} ${cut.isManager ? 'manager' : 'player'}`;
      if (cut.image) { this.cutInImg.src = cut.image; this.cutInImg.style.display = 'block'; }
      else { this.cutInImg.style.display = 'none'; }
      this.cutInBanner.textContent = (cut.isManager ? '🎯 ' : '') + cut.title;
      this.cutInBanner.style.background = cut.color;
      // 再アニメーション用にクラス再付与
      this.cutInEl.classList.remove('anim');
      void this.cutInEl.offsetWidth;
      this.cutInEl.classList.add('anim');
    }
  }
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}
