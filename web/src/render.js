// pitch.js（Three.js 描画）を流用したレンダラ。
// createPitch() でシーンを構築し、applyState(s) で 1 フレーム分の状態を反映する。
// 座標系は Swift / engine.js と一致：x=横, y=高さ, z=縦（home は -z を攻める）。
import * as THREE from 'three';

const FIELD_LENGTH = 42;
const FIELD_WIDTH = 26;
const GOAL_WIDTH = 6;
const GOAL_HEIGHT = 2.4;
const HW = FIELD_WIDTH / 2;
const HL = FIELD_LENGTH / 2;

export function createPitch(mountEl) {
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
  (mountEl || document.body).appendChild(renderer.domElement);

  // --- ライト ---
  scene.add(new THREE.HemisphereLight(0xbfd8ff, 0x35502f, 0.85));
  const sun = new THREE.DirectionalLight(0xffffff, 1.1);
  sun.position.set(18, 40, 24);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  sun.shadow.camera.near = 1;
  sun.shadow.camera.far = 120;
  sun.shadow.camera.left = -40;
  sun.shadow.camera.right = 40;
  sun.shadow.camera.top = 40;
  sun.shadow.camera.bottom = -40;
  scene.add(sun);

  // --- ピッチ ---
  const grass = new THREE.Mesh(
    new THREE.PlaneGeometry(FIELD_WIDTH + 8, FIELD_LENGTH + 8),
    new THREE.MeshStandardMaterial({ color: 0x1f7a37, roughness: 0.95 })
  );
  grass.rotation.x = -Math.PI / 2;
  grass.receiveShadow = true;
  scene.add(grass);

  // 芝のストライプ
  for (let i = 0; i < 8; i++) {
    const stripe = new THREE.Mesh(
      new THREE.PlaneGeometry(FIELD_WIDTH, FIELD_LENGTH / 8),
      new THREE.MeshStandardMaterial({ color: i % 2 ? 0x238a3f : 0x1d6f33, roughness: 0.95 })
    );
    stripe.rotation.x = -Math.PI / 2;
    stripe.position.set(0, 0.01, -HL + (i + 0.5) * (FIELD_LENGTH / 8));
    stripe.receiveShadow = true;
    scene.add(stripe);
  }

  // --- ライン ---
  const lineMat = new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.7 });
  function addLines(points, loop) {
    const geo = new THREE.BufferGeometry().setFromPoints(
      points.map((p) => new THREE.Vector3(p[0], 0.02, p[1]))
    );
    scene.add(loop ? new THREE.LineLoop(geo, lineMat) : new THREE.Line(geo, lineMat));
  }
  addLines([[-HW, -HL], [HW, -HL], [HW, HL], [-HW, HL]], true); // 外枠
  addLines([[-HW, 0], [HW, 0]], false); // ハーフウェイ
  const circle = [];
  for (let i = 0; i <= 48; i++) {
    const a = (i / 48) * Math.PI * 2;
    circle.push([Math.cos(a) * 4.5, Math.sin(a) * 4.5]);
  }
  addLines(circle, true); // センターサークル

  // --- ゴール ---
  function makeGoal(z, color) {
    const g = new THREE.Group();
    const postMat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.4 });
    const r = 0.12;
    const halfW = GOAL_WIDTH / 2;
    const postGeo = new THREE.CylinderGeometry(r, r, GOAL_HEIGHT, 12);
    for (const x of [-halfW, halfW]) {
      const post = new THREE.Mesh(postGeo, postMat);
      post.position.set(x, GOAL_HEIGHT / 2, z);
      post.castShadow = true;
      g.add(post);
    }
    const barGeo = new THREE.CylinderGeometry(r, r, GOAL_WIDTH, 12);
    const bar = new THREE.Mesh(barGeo, postMat);
    bar.rotation.z = Math.PI / 2;
    bar.position.set(0, GOAL_HEIGHT, z);
    bar.castShadow = true;
    g.add(bar);
    // ネット（簡易）
    const netMat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.18, side: THREE.DoubleSide, wireframe: true });
    const depth = 2;
    const dz = z < 0 ? -depth : depth;
    const back = new THREE.Mesh(new THREE.PlaneGeometry(GOAL_WIDTH, GOAL_HEIGHT, 8, 4), netMat);
    back.position.set(0, GOAL_HEIGHT / 2, z + dz);
    g.add(back);
    return g;
  }
  scene.add(makeGoal(-HL, 0x66ccff));
  scene.add(makeGoal(HL, 0xff8866));

  // --- スタンド ---
  function makeStand(x, z, w, d, rotY) {
    const g = new THREE.Group();
    const base = new THREE.Mesh(
      new THREE.BoxGeometry(w, 3, d),
      new THREE.MeshStandardMaterial({ color: 0x223044, roughness: 0.9 })
    );
    base.position.y = 1.5;
    base.castShadow = true;
    base.receiveShadow = true;
    g.add(base);
    // 観客（点描）
    const dotGeo = new THREE.SphereGeometry(0.18, 6, 6);
    const colors = [0xff5555, 0x55aaff, 0xffff66, 0xffffff, 0x66ff99];
    for (let i = 0; i < 120; i++) {
      const m = new THREE.Mesh(dotGeo, new THREE.MeshStandardMaterial({ color: colors[i % colors.length] }));
      m.position.set((Math.random() - 0.5) * w, 3 + Math.random() * 1.2, (Math.random() - 0.5) * d);
      g.add(m);
    }
    g.position.set(x, 0, z);
    g.rotation.y = rotY;
    return g;
  }
  scene.add(makeStand(-(HW + 6), 0, 10, FIELD_LENGTH, 0));
  scene.add(makeStand(HW + 6, 0, 10, FIELD_LENGTH, 0));

  // --- ボール ---
  const ball = new THREE.Mesh(
    new THREE.SphereGeometry(0.22, 24, 24),
    new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.35 })
  );
  ball.castShadow = true;
  ball.userData.tgt = null;
  scene.add(ball);
  const ballPrev = new THREE.Vector3();

  // --- 選手 ---
  const teamShirt = { home: 0x2a6df0, away: 0xe23b3b };
  const teamShorts = { home: 0xffffff, away: 0x222222 };

  function mat(color, rough = 0.7) { return new THREE.MeshStandardMaterial({ color, roughness: rough }); }
  function limb(w, h, d, color) {
    const grp = new THREE.Group();
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(color));
    m.position.y = -h / 2;
    m.castShadow = true;
    grp.add(m);
    return grp;
  }

  function makePlayer(side, keeper) {
    const g = new THREE.Group();
    const shirt = keeper ? 0x33dd88 : teamShirt[side];
    const shorts = keeper ? 0x115522 : teamShorts[side];
    const skin = 0xf0c8a0;

    const hip = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.3, 0.32), mat(shorts));
    hip.position.y = 0.92;
    hip.castShadow = true;
    g.add(hip);

    const torso = new THREE.Mesh(new THREE.BoxGeometry(0.56, 0.62, 0.34), mat(shirt));
    torso.position.y = 1.4;
    torso.castShadow = true;
    g.add(torso);

    const head = new THREE.Mesh(new THREE.SphereGeometry(0.2, 16, 16), mat(skin));
    head.position.y = 1.92;
    head.castShadow = true;
    g.add(head);

    const armL = limb(0.16, 0.6, 0.16, shirt); armL.position.set(-0.36, 1.66, 0);
    const armR = limb(0.16, 0.6, 0.16, shirt); armR.position.set(0.36, 1.66, 0);
    const legL = limb(0.2, 0.78, 0.2, shorts); legL.position.set(-0.14, 0.92, 0);
    const legR = limb(0.2, 0.78, 0.2, shorts); legR.position.set(0.14, 0.92, 0);
    g.add(armL, armR, legL, legR);

    // 操作リング
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.7, 0.07, 8, 32),
      new THREE.MeshBasicMaterial({ color: 0xffe600 })
    );
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.05;
    ring.visible = false;
    g.add(ring);

    g.userData = {
      tgt: new THREE.Vector3(), cur: new THREE.Vector3(), initialized: false,
      facing: side === 'home' ? Math.PI : 0, phase: Math.random() * 6,
      torso, armL, armR, legL, legR, hip, ring,
    };
    scene.add(g);
    return g;
  }

  const players = new Map();

  function hexToInt(h) {
    if (typeof h !== 'string') return null;
    const s = h.replace('#', '');
    const n = parseInt(s, 16);
    return Number.isFinite(n) ? n : null;
  }

  function applyState(s) {
    if (s.homeShirt) { const c = hexToInt(s.homeShirt); if (c != null) teamShirt.home = c; }
    if (s.awayShirt) { const c = hexToInt(s.awayShirt); if (c != null) teamShirt.away = c; }
    if (s.homeShorts) { const c = hexToInt(s.homeShorts); if (c != null) teamShorts.home = c; }
    if (s.awayShorts) { const c = hexToInt(s.awayShorts); if (c != null) teamShorts.away = c; }
    if (s.ball) ball.userData.tgt = s.ball;
    if (Array.isArray(s.players)) {
      for (const p of s.players) {
        let g = players.get(p.id);
        if (!g) { g = makePlayer(p.side, p.keeper); players.set(p.id, g); }
        const u = g.userData;
        u.tgt.set(p.x, 0, p.z);
        if (!u.initialized) { u.cur.set(p.x, 0, p.z); g.position.copy(u.cur); u.initialized = true; }
        u.ring.visible = !!p.ctrl;
        if (!p.keeper) {
          const shirt = p.ctrl ? 0xffe600 : teamShirt[p.side];
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

  // 補間 + アニメーション
  let lastT = performance.now();
  function frame(now) {
    const dt = Math.min((now - lastT) / 1000, 0.05);
    lastT = now;

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

    players.forEach((g) => {
      const u = g.userData;
      const prevX = g.position.x, prevZ = g.position.z;
      u.cur.lerp(u.tgt, 0.25);
      g.position.set(u.cur.x, 0, u.cur.z);

      const vx = g.position.x - prevX, vz = g.position.z - prevZ;
      const speed = Math.hypot(vx, vz) / dt;

      if (speed > 0.3) {
        const targetFacing = Math.atan2(vx, vz);
        let diff = targetFacing - u.facing;
        while (diff > Math.PI) diff -= Math.PI * 2;
        while (diff < -Math.PI) diff += Math.PI * 2;
        u.facing += diff * 0.2;
      }
      g.rotation.y = u.facing;

      const amp = Math.min(speed * 0.12, 0.9);
      u.phase += dt * (4 + speed * 1.6);
      const sw = Math.sin(u.phase) * amp;
      u.legL.rotation.x = sw;
      u.legR.rotation.x = -sw;
      u.armL.rotation.x = -sw * 0.8;
      u.armR.rotation.x = sw * 0.8;
      u.torso.rotation.x = Math.min(speed * 0.03, 0.25);
      g.position.y = Math.abs(Math.sin(u.phase)) * amp * 0.08;

      if (u.ring.visible) u.ring.rotation.z += dt * 2;
    });

    renderer.render(scene, camera);
  }

  window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  });

  return { applyState, frame, renderer, scene, camera };
}
