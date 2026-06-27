// ピッチ寸法・物理係数。Swift の GameConstants.swift と一致させる。
// 座標系は Three.js と揃える：x=横（右が+）, y=上, z=縦（相手ゴール方向が -z）。

export const Pitch = {
  length: 42, // z 方向の全長（m）
  width: 26, // x 方向の全幅（m）
  goalWidth: 6,
  goalHeight: 2.4,
  get ownGoalZ() { return this.length / 2; }, // 自陣ゴールライン z（守る）
  get enemyGoalZ() { return -this.length / 2; }, // 相手ゴールライン z（攻める）
};

export const Roster = {
  fieldPlayers: 4,
  total: 5,
};

export const BallPhysics = {
  groundDamping: 0.55,
  gravity: 9.8,
  restitution: 0.55,
  maxShotSpeed: 24,
  radius: 0.22,
};
