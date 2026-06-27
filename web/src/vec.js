// Swift の simd を最小限で代替する 2D ベクトルヘルパ。
// 選手座標は {x, z}（ピッチ平面）、ボールは {x, y, z}（y=高さ）。

export const v2 = (x = 0, z = 0) => ({ x, z });

export const add = (a, b) => ({ x: a.x + b.x, z: a.z + b.z });
export const sub = (a, b) => ({ x: a.x - b.x, z: a.z - b.z });
export const scale = (a, s) => ({ x: a.x * s, z: a.z * s });
export const dot = (a, b) => a.x * b.x + a.z * b.z;
export const length = (a) => Math.hypot(a.x, a.z);

export function normalize(a) {
  const l = length(a);
  return l > 0 ? { x: a.x / l, z: a.z / l } : { x: 0, z: 0 };
}

export const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
export const mix = (a, b, t) => a + (b - a) * t; // simd_mix 相当（線形補間）
