// AudioFX.swift の移植：効果音。
//   - 環境音(stadium)・歓声(cheer) は mp3 を <audio> で再生
//   - キック/ホイッスル/チャンス合図は WebAudio でプログラム合成
// ブラウザの自動再生制限のため、最初のユーザー操作後に start() すること。

export class AudioFX {
  constructor() {
    this.ctx = null;
    this.started = false;
    this.kickBuf = null;
    this.whistleBuf = null;
    this.chanceCueBuf = null;

    this.stadium = mkAudio('./assets/audio/stadium.mp3', true, 0.5);
    this.cheer = mkAudio('./assets/audio/cheer.mp3', false, 0.9);
  }

  start() {
    if (this.started) return;
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return;
    this.ctx = new Ctx();
    this._buildBuffers();
    this.started = true;
    if (this.ctx.state === 'suspended') this.ctx.resume();
  }

  stop() {
    this.stadium?.pause();
    this.cheer?.pause();
    this.ctx?.close?.();
    this.ctx = null;
    this.started = false;
  }

  // MARK: - イベント
  kick() { this._play(this.kickBuf, 0.9); }
  whistle() { this._play(this.whistleBuf, 1); }
  chanceCue() { this._play(this.chanceCueBuf, 1); }

  startAmbient() {
    if (!this.stadium) return;
    this.stadium.currentTime = 0;
    this.stadium.play().catch(() => {});
  }

  goal() { this._cheer(0.95); }
  save() { this._cheer(0.7); }
  conceded() { this._play(this.whistleBuf, 1); }

  _cheer(vol) {
    if (!this.cheer) return;
    this.cheer.currentTime = 0;
    this.cheer.volume = vol;
    this.cheer.play().catch(() => {});
  }

  // MARK: - 合成
  _play(buf, gain = 1) {
    if (!this.started || !buf || !this.ctx) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const g = this.ctx.createGain();
    g.gain.value = gain;
    src.connect(g).connect(this.ctx.destination);
    src.start();
  }

  _buildBuffers() {
    this.kickBuf = this._render(0.18, (t) => {
      const env = Math.exp(-t * 28);
      const tone = Math.sin(2 * Math.PI * 110 * t) * env;
      const click = t < 0.02 ? (Math.random() * 2 - 1) * Math.exp(-t * 200) : 0;
      return (tone * 0.9 + click * 0.5) * 0.6;
    });
    this.whistleBuf = this._render(0.45, (t) => {
      const f = 2550 + Math.sin(2 * Math.PI * 16 * t) * 120;
      const attack = Math.min(t / 0.02, 1);
      const release = t > 0.3 ? Math.max(0, 1 - (t - 0.3) / 0.15) : 1;
      const env = attack * release;
      return (Math.sin(2 * Math.PI * f * t) + Math.sin(2 * Math.PI * f * 2 * t) * 0.3) * env * 0.4;
    });
    this.chanceCueBuf = this._render(0.34, (t) => {
      const b1 = t < 0.12 ? Math.sin(2 * Math.PI * 880 * t) : 0;
      const b2 = t > 0.16 && t < 0.3 ? Math.sin(2 * Math.PI * 1320 * t) : 0;
      return (b1 + b2) * Math.exp(-(t % 0.16) * 8) * 0.35;
    });
  }

  _render(seconds, fill) {
    const sr = this.ctx.sampleRate;
    const frames = Math.floor(seconds * sr);
    const buf = this.ctx.createBuffer(2, frames, sr);
    for (let c = 0; c < 2; c++) {
      const data = buf.getChannelData(c);
      for (let i = 0; i < frames; i++) data[i] = fill(i / sr);
    }
    return buf;
  }
}

function mkAudio(url, loop, volume) {
  const a = new Audio(url);
  a.loop = loop;
  a.volume = volume;
  a.preload = 'auto';
  return a;
}

// タイトル BGM（MusicPlayer 相当）。
export function makeTitleBGM() {
  return mkAudio('./assets/audio/title.mp3', true, 0.55);
}
