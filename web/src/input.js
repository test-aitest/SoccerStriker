// キーボード入力。iPhone を「振る」操作の代替。
//   - チャンスのゲージに対して 1 押下 = 1 スイング。
//       * 連打パワー型：素早く連打してバーを溜める
//       * タイミング型：当たりゾーンで 1 回押す
//   - Esc：タイトルへ戻る
// OS のキーリピート（押しっぱなし）は e.repeat で無視 → 連打を実力勝負にする。

const SWING_KEYS = new Set([
  'Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Enter',
]);

export function attachInput({ onSwing, onEscape }) {
  const handler = (e) => {
    if (e.code === 'Escape') { onEscape?.(); return; }
    if (SWING_KEYS.has(e.code)) {
      e.preventDefault();
      if (e.repeat) return; // 押しっぱなしの自動リピートは数えない
      onSwing?.();
    }
  };
  window.addEventListener('keydown', handler);
  return () => window.removeEventListener('keydown', handler);
}
