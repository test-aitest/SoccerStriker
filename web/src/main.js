// エントリ：タイトル → 国選択 → 試合 の画面遷移を束ねる。
// SoccerStrikerMac の RootView/MatchView 相当をブラウザで再現する。

import { createPitch } from './render.js';
import { Game } from './game.js';
import { HUD } from './hud.js';
import { attachInput } from './input.js';
import { AudioFX, makeTitleBGM } from './audio.js';
import { showTitle, showSelect } from './screens.js';

const sceneEl = document.getElementById('scene');
const uiEl = document.getElementById('ui');

let pitch = null; // three.js レンダラ（初回試合で生成し再利用）
let game = null;
let hud = null;
let detachInput = null;
let mode = 'title'; // 'title' | 'select' | 'match'

const titleBGM = makeTitleBGM();
const audio = new AudioFX();

// 最初のユーザー操作で音声を解放（自動再生制限対策）。
function unlockAudioOnce() {
  titleBGM.play().catch(() => {});
  window.removeEventListener('pointerdown', unlockAudioOnce);
  window.removeEventListener('keydown', unlockAudioOnce);
}
window.addEventListener('pointerdown', unlockAudioOnce);
window.addEventListener('keydown', unlockAudioOnce);

// --- 画面遷移 ---
function goTitle() {
  mode = 'title';
  cleanupMatch();
  sceneEl.classList.add('dimmed');
  titleBGM.play().catch(() => {});
  showTitle(uiEl, { onStart: goSelect });
}

function goSelect() {
  mode = 'select';
  titleBGM.play().catch(() => {});
  showSelect(uiEl, { onStart: goMatch, onBack: goTitle });
}

function goMatch(home, away) {
  mode = 'match';
  uiEl.innerHTML = '';
  sceneEl.classList.remove('dimmed');
  titleBGM.pause();

  if (!pitch) pitch = createPitch(sceneEl);

  game = new Game(home, away, audio);
  hud = new HUD(uiEl, home, away);
  game.start();

  detachInput = attachInput({
    onSwing: () => game.registerKick(),
    onEscape: goTitle,
  });
}

function cleanupMatch() {
  if (detachInput) { detachInput(); detachInput = null; }
  if (game) { game = null; }
  if (hud) { hud = null; }
  audio.stop();
}

// --- メインループ（rAF）---
let last = performance.now();
function loop(now) {
  requestAnimationFrame(loop);
  const dt = (now - last) / 1000;
  last = now;

  if (mode === 'match' && game && pitch) {
    game.tick(dt);
    pitch.applyState(game.renderState());
    hud.update(game);
  }
  if (pitch) pitch.frame(now);
}

requestAnimationFrame(loop);
goTitle();
