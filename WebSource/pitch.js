// Soccer Striker — 4vs4 ピッチの 3D ビュー。
// Swift(SoccerEngine) から 60Hz で送られる "state" コマンドを受けて
// ボール・選手・スコアを描画する。座標系は Swift と一致：
//   x = ピッチ横, y = 高さ, z = ピッチ縦（home は -z を攻める）。
import * as THREE from 'three';

// --- 寸法（Swift の Pitch と一致させる）---
const FIELD_LENGTH = 42;
const FIELD_WIDTH = 26;
const GOAL_WIDTH = 6;
const GOAL_HEIGHT = 2.4;
const HW = FIELD_WIDTH / 2;
const HL = FIELD_LENGTH / 2;

const errEl = document.getElementById('fallback-error');
function showError(msg) { if (errEl) errEl.textContent = msg; }

// ============================================================
// 基本セットアップ
// ============================================================
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0a1424);
scene.fog = new THREE.Fog(0x0a1424, 60, 130);

const camera = new THREE.PerspectiveCamera(48, window.innerWidth / window.innerHeight, 0.1, 500);
camera.position.set(0, 22, HL + 18);
camera.lookAt(0, 0, -2);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.15;
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.body.appendChild(renderer.domElement);

// --- ライト ---
scene.add(new THREE.HemisphereLight(0xbfd8ff, 0x35502f, 0.85));
const sun = new THREE.DirectionalLight(0xffffff, 2.2);
sun.position.set(16, 34, 20);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.camera.left = -32; sun.shadow.camera.right = 32;
sun.shadow.camera.top = 32; sun.shadow.camera.bottom = -32;
sun.shadow.bias = -0.0004;
scene.add(sun);

// ============================================================
// ピッチ（芝ストライプ + ライン + ペナルティエリア）
// ============================================================
const pitchGroup = new THREE.Group();
scene.add(pitchGroup);

const stripes = 12;
for (let i = 0; i < stripes; i++) {
  const w = FIELD_LENGTH / stripes;
  const mat = new THREE.MeshStandardMaterial({ color: i % 2 ? 0x2f8a36 : 0x2a7d31, roughness: 0.95 });
  const m = new THREE.Mesh(new THREE.PlaneGeometry(FIELD_WIDTH, w), mat);
  m.rotation.x = -Math.PI / 2;
  m.position.z = -HL + w * (i + 0.5);
  m.receiveShadow = true;
  pitchGroup.add(m);
}
// 場外の暗い地面
{
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(FIELD_WIDTH + 40, FIELD_LENGTH + 40),
    new THREE.MeshStandardMaterial({ color: 0x14361a, roughness: 1 })
  );
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -0.02;
  ground.receiveShadow = true;
  scene.add(ground);
}

const lineMat = new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.85 });
function addLines(points, loop) {
  const geo = new THREE.BufferGeometry().setFromPoints(points.map(p => new THREE.Vector3(p[0], 0.03, p[1])));
  pitchGroup.add(loop ? new THREE.LineLoop(geo, lineMat) : new THREE.Line(geo, lineMat));
}
addLines([[-HW, -HL], [HW, -HL], [HW, HL], [-HW, HL]], true);     // 外周
addLines([[-HW, 0], [HW, 0]]);                                     // センターライン
// センターサークル
{
  const seg = 56, r = 4, pts = [];
  for (let i = 0; i <= seg; i++) { const a = i / seg * Math.PI * 2; pts.push([Math.cos(a) * r, Math.sin(a) * r]); }
  addLines(pts);
}
// ペナルティエリア（両ゴール前）
const PA_W = 12, PA_D = 6;
for (const s of [-1, 1]) {
  const z0 = s * HL, z1 = s * (HL - PA_D);
  addLines([[-PA_W / 2, z0], [-PA_W / 2, z1], [PA_W / 2, z1], [PA_W / 2, z0]]);
}

// ============================================================
// ゴール（ネット付き）
// ============================================================
function makeGoal(z, color) {
  const g = new THREE.Group();
  const postMat = new THREE.MeshStandardMaterial({ color, roughness: 0.4, metalness: 0.1 });
  const postGeo = new THREE.CylinderGeometry(0.1, 0.1, GOAL_HEIGHT, 12);
  for (const sx of [-GOAL_WIDTH / 2, GOAL_WIDTH / 2]) {
    const post = new THREE.Mesh(postGeo, postMat);
    post.position.set(sx, GOAL_HEIGHT / 2, z);
    post.castShadow = true; g.add(post);
  }
  const bar = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.1, GOAL_WIDTH, 12), postMat);
  bar.rotation.z = Math.PI / 2; bar.position.set(0, GOAL_HEIGHT, z); bar.castShadow = true; g.add(bar);
  // ネット（半透明）
  const depth = 1.4;
  const netMat = new THREE.MeshStandardMaterial({ color: 0xffffff, transparent: true, opacity: 0.12, side: THREE.DoubleSide });
  const back = new THREE.Mesh(new THREE.PlaneGeometry(GOAL_WIDTH, GOAL_HEIGHT), netMat);
  back.position.set(0, GOAL_HEIGHT / 2, z + Math.sign(z) * depth);
  g.add(back);
  scene.add(g);
}
makeGoal(-HL, 0xff8c42);  // home が攻めるゴール
makeGoal(HL, 0x42c6ff);   // home が守るゴール

// ============================================================
// 観客スタンド（雰囲気づくり）
// ============================================================
function makeStand(x, z, w, d, rotY) {
  const g = new THREE.Group();
  const base = new THREE.Mesh(
    new THREE.BoxGeometry(w, 3, d),
    new THREE.MeshStandardMaterial({ color: 0x20262e, roughness: 1 })
  );
  base.position.y = 1.5; g.add(base);
  // 観客＝小さな色付きインスタンス
  const dotGeo = new THREE.BoxGeometry(0.4, 0.4, 0.4);
  const colors = [0xff5a5a, 0x5ad1ff, 0xffe45a, 0xffffff, 0x9b8cff];
  const cols = Math.floor(w / 0.7), rows = 4;
  const inst = new THREE.InstancedMesh(dotGeo, new THREE.MeshStandardMaterial({ vertexColors: false }), cols * rows);
  const dummy = new THREE.Object3D(); let i = 0;
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    dummy.position.set(-w / 2 + 0.4 + c * 0.7, 2.0 + r * 0.5, -d / 2 + 0.3 + (r * 0.13));
    dummy.updateMatrix(); inst.setMatrixAt(i, dummy.matrix);
    inst.setColorAt(i, new THREE.Color(colors[(r + c) % colors.length])); i++;
  }
  g.add(inst);
  g.position.set(x, 0, z); g.rotation.y = rotY;
  scene.add(g);
}
makeStand(0, HL + 6, FIELD_WIDTH + 8, 5, 0);
makeStand(0, -HL - 6, FIELD_WIDTH + 8, 5, Math.PI);
makeStand(HW + 6, 0, FIELD_LENGTH, 5, -Math.PI / 2);
makeStand(-HW - 6, 0, FIELD_LENGTH, 5, Math.PI / 2);

// ============================================================
// ボール
// ============================================================
const ball = new THREE.Mesh(
  new THREE.SphereGeometry(0.22, 28, 28),
  new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.35, metalness: 0.05 })
);
ball.castShadow = true;
scene.add(ball);
let ballPrev = new THREE.Vector3();

// ============================================================
// 立体的な選手モデル（プリミティブ人型 + 走りアニメ）
// ============================================================
function mat(color, rough = 0.7) { return new THREE.MeshStandardMaterial({ color, roughness: rough }); }

/// 股関節/肩で回転させる手足。group を回すと pivot から振れる。
function limb(w, h, d, color) {
  const pivot = new THREE.Group();
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(color));
  m.position.y = -h / 2;     // 上端を pivot に合わせる
  m.castShadow = true;
  pivot.add(m);
  return pivot;
}

const TEAM = {
  home: { jersey: 0x1565c0, shorts: 0xffffff, sock: 0x1565c0 },
  away: { jersey: 0xc62828, shorts: 0x1a1a1a, sock: 0xc62828 },
};
const SKIN = 0xf1c39a;

function makePlayer(side, keeper) {
  const t = TEAM[side];
  const g = new THREE.Group();

  // 胴体
  const torso = new THREE.Mesh(new THREE.BoxGeometry(0.56, 0.66, 0.3), mat(keeper ? 0x2e7d32 : t.jersey));
  torso.position.y = 1.18; torso.castShadow = true; g.add(torso);
  // 腰
  const hip = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.22, 0.28), mat(t.shorts));
  hip.position.y = 0.82; hip.castShadow = true; g.add(hip);
  // 首 + 頭
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.2, 18, 18), mat(SKIN, 0.5));
  head.position.y = 1.66; head.castShadow = true; g.add(head);
  const hair = new THREE.Mesh(new THREE.SphereGeometry(0.205, 16, 16, 0, Math.PI * 2, 0, Math.PI * 0.55), mat(0x2a2118, 0.8));
  hair.position.y = 1.69; g.add(hair);

  // 手足（pivot 付き）
  const legL = limb(0.2, 0.72, 0.22, t.sock); legL.position.set(-0.15, 0.82, 0);
  const legR = limb(0.2, 0.72, 0.22, t.sock); legR.position.set(0.15, 0.82, 0);
  const armL = limb(0.16, 0.6, 0.16, keeper ? 0x2e7d32 : t.jersey); armL.position.set(-0.34, 1.45, 0);
  const armR = limb(0.16, 0.6, 0.16, keeper ? 0x2e7d32 : t.jersey); armR.position.set(0.34, 1.45, 0);
  g.add(legL, legR, armL, armR);

  // 足元の影代わりの暗い円（接地感）
  const blob = new THREE.Mesh(
    new THREE.CircleGeometry(0.4, 20),
    new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.25 })
  );
  blob.rotation.x = -Math.PI / 2; blob.position.y = 0.04; g.add(blob);

  // 操作中リング（home の操作選手だけ表示）
  const ring = new THREE.Mesh(
    new THREE.RingGeometry(0.5, 0.66, 28),
    new THREE.MeshBasicMaterial({ color: 0xffe600, transparent: true, opacity: 0.9, side: THREE.DoubleSide })
  );
  ring.rotation.x = -Math.PI / 2; ring.position.y = 0.05; ring.visible = false; g.add(ring);

  g.userData = {
    legL, legR, armL, armR, torso, hip, head,
    ring, phase: Math.random() * 6.28,
    cur: new THREE.Vector3(), tgt: new THREE.Vector3(),
    facing: side === 'home' ? Math.PI : 0, initialized: false,
  };
  scene.add(g);
  return g;
}

const players = new Map(); // id -> group

// チームカラー（Swift から hex で届く）。shirt=上着, shorts=パンツ。
const teamShirt = { home: 0x33b5ff, away: 0xff7043 };
const teamShorts = { home: 0xffffff, away: 0x222222 };
function hexToInt(h) {
  if (typeof h !== 'string') return null;
  return parseInt(h.replace('#', ''), 16);
}

function applyState(s) {
  if (s.homeShirt)  { const c = hexToInt(s.homeShirt);  if (c != null) teamShirt.home = c; }
  if (s.awayShirt)  { const c = hexToInt(s.awayShirt);  if (c != null) teamShirt.away = c; }
  if (s.homeShorts) { const c = hexToInt(s.homeShorts); if (c != null) teamShorts.home = c; }
  if (s.awayShorts) { const c = hexToInt(s.awayShorts); if (c != null) teamShorts.away = c; }
  if (s.ball) {
    ball.userData.tgt = s.ball;
  }
  if (Array.isArray(s.players)) {
    for (const p of s.players) {
      let g = players.get(p.id);
      if (!g) { g = makePlayer(p.side, p.keeper); players.set(p.id, g); }
      const u = g.userData;
      u.tgt.set(p.x, 0, p.z);
      if (!u.initialized) { u.cur.set(p.x, 0, p.z); g.position.copy(u.cur); u.initialized = true; }
      u.ring.visible = !!p.ctrl;
      // ユニフォーム色を反映（上着=torso+腕, パンツ=腰+脚。操作中は足元リングで示す。GKは緑のまま）。
      if (!p.keeper) {
        const shirt = teamShirt[p.side];
        const shorts = teamShorts[p.side];
        if (u.torso) u.torso.material.color.setHex(shirt);
        if (u.armL) u.armL.children[0].material.color.setHex(shirt);
        if (u.armR) u.armR.children[0].material.color.setHex(shirt);
        if (u.hip) u.hip.material.color.setHex(shorts);
        if (u.legL) u.legL.children[0].material.color.setHex(shorts);
        if (u.legR) u.legR.children[0].material.color.setHex(shorts);
      }
    }
  }
}

// ============================================================
// 補間 + アニメーション
// ============================================================
let lastT = performance.now();
function animate(now) {
  requestAnimationFrame(animate);
  const dt = Math.min((now - lastT) / 1000, 0.05);
  lastT = now;

  // ボール：目標へ補間 + 進行方向へ回転
  if (ball.userData.tgt) {
    const t = ball.userData.tgt;
    ballPrev.copy(ball.position);
    ball.position.lerp(new THREE.Vector3(t.x, t.y, t.z), 0.4);
    const dx = ball.position.x - ballPrev.x, dz = ball.position.z - ballPrev.z;
    const horiz = Math.hypot(dx, dz);
    if (horiz > 0.0001) {
      const axis = new THREE.Vector3(dz, 0, -dx).normalize();
      ball.rotateOnWorldAxis(axis, horiz / 0.22);
    }
  }

  // 選手：目標へ補間 + 走りアニメ + 向き
  players.forEach((g) => {
    const u = g.userData;
    const prevX = g.position.x, prevZ = g.position.z;
    u.cur.lerp(u.tgt, 0.25);
    g.position.set(u.cur.x, 0, u.cur.z);

    const vx = g.position.x - prevX, vz = g.position.z - prevZ;
    const speed = Math.hypot(vx, vz) / dt; // m/s 概算

    // 進行方向へ滑らかに向く
    if (speed > 0.3) {
      const targetFacing = Math.atan2(vx, vz);
      let diff = targetFacing - u.facing;
      while (diff > Math.PI) diff -= Math.PI * 2;
      while (diff < -Math.PI) diff += Math.PI * 2;
      u.facing += diff * 0.2;
    }
    g.rotation.y = u.facing;

    // 走りアニメ：速いほど大きく速く振る
    const amp = Math.min(speed * 0.12, 0.9);
    u.phase += dt * (4 + speed * 1.6);
    const sw = Math.sin(u.phase) * amp;
    u.legL.rotation.x = sw;
    u.legR.rotation.x = -sw;
    u.armL.rotation.x = -sw * 0.8;
    u.armR.rotation.x = sw * 0.8;
    // 走行中は前傾 + 上下バウンド
    u.torso.rotation.x = Math.min(speed * 0.03, 0.25);
    g.position.y = Math.abs(Math.sin(u.phase)) * amp * 0.08;

    // 操作リングは回転させて目立たせる
    if (u.ring.visible) u.ring.rotation.z += dt * 2;
  });

  renderer.render(scene, camera);
}

// ============================================================
// Swift ブリッジ
// ============================================================
if (window.WebScene && window.WebScene.isEmbedded) {
  window.WebScene.onCommand((cmd) => {
    if (cmd && cmd.type === 'state' && cmd.payload) {
      try { applyState(cmd.payload); } catch (e) { showError(String(e)); }
    }
  });
}

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

requestAnimationFrame(animate);

if (window.WebScene) {
  window.WebScene.ready();
  window.WebScene.enableFPSReporting(2000);
}

// ============================================================
// デモモード：ブラウザで直接開いた（= 非埋め込み）ときだけ、
// 選手とボールを動かして見た目を確認できるようにする。
// Mac アプリ内では Swift の state が来るのでこのブロックは無効。
// ============================================================
if (!(window.WebScene && window.WebScene.isEmbedded)) {
  const form = [
    [0, HL - 1, true], [-HW / 2, HL / 2, false], [HW / 2, HL / 2, false], [0, HL / 4, false], [0, 2, false],
  ];
  const demo = { t: 0 };
  function demoTick() {
    demo.t += 0.016;
    const bx = Math.sin(demo.t * 0.7) * 8;
    const bz = Math.sin(demo.t * 0.5) * 12;
    const ps = [];
    let id = 0;
    for (const [x, z, k] of form) { ps.push({ id: id++, side: 'home', keeper: k, x: x + Math.sin(demo.t + id) * 1.5, z: z + Math.cos(demo.t + id) * 1.5, ctrl: id === 5 }); }
    for (const [x, z, k] of form) { ps.push({ id: id++, side: 'away', keeper: k, x: -x + Math.cos(demo.t + id), z: -z + Math.sin(demo.t + id), ctrl: false }); }
    applyState({ ball: { x: bx, y: 0.22 + Math.abs(Math.sin(demo.t * 2)) * 1.5, z: bz }, players: ps });
    setTimeout(demoTick, 16);
  }
  demoTick();
}
