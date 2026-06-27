// RootView.swift / CountrySelectView.swift の移植：タイトル画面と国選択画面。
// それぞれ DOM を root に構築し、コールバックで次の画面へ遷移する。

import { COUNTRIES, JAPAN, BRAZIL, flagImg, playerURL, flagURL } from './countries.js';

// MARK: - タイトル
export function showTitle(root, { onStart }) {
  root.innerHTML = '';
  const screen = el('div', 'screen title-screen');
  screen.innerHTML = `
    <h1 class="title-logo">SOCCER STRIKER</h1>
    <p class="title-sub">4 vs 4 · 連打＆タイミングで決める</p>
  `;
  const btn = el('button', 'big-btn', 'KICK OFF');
  btn.addEventListener('click', onStart);
  screen.appendChild(btn);
  screen.appendChild(el('p', 'title-note',
    '両チームは AI が自動でプレイします。\nチャンス/ピンチでゲージが出たら ↑キー連打 / Space で介入！'));
  root.appendChild(screen);
  return () => { root.innerHTML = ''; };
}

// MARK: - 国選択
export function showSelect(root, { onStart, onBack }) {
  root.innerHTML = '';
  let home = JAPAN;
  let away = BRAZIL;
  let editing = 'home'; // 'home' | 'away'

  const screen = el('div', 'screen select-screen');

  // ヘッダ
  const header = el('div', 'select-header');
  const back = el('button', 'icon-btn', '‹');
  back.addEventListener('click', onBack);
  header.append(back, el('h2', 'select-title', 'SELECT MATCH'));
  screen.appendChild(header);

  // 対戦カード（YOU vs CPU）
  const matchup = el('div', 'matchup');
  const homePod = podium('home', 'YOU');
  const vs = el('div', 'matchup-vs', 'VS');
  const awayPod = podium('away', 'CPU');
  matchup.append(homePod.wrap, vs, awayPod.wrap);
  screen.appendChild(matchup);

  // 国旗グリッド
  const grid = el('div', 'flag-grid');
  const cells = COUNTRIES.map((c) => {
    const cell = el('button', 'flag-cell');
    cell.appendChild(flagImg(c, 34));
    cell.appendChild(el('div', 'flag-cell-name', c.name));
    cell.style.background = hexA(c.primaryHex, 0.18);
    cell.addEventListener('click', () => pick(c));
    cell._country = c;
    grid.appendChild(cell);
    return cell;
  });
  screen.appendChild(grid);

  // START
  const start = el('button', 'big-btn', 'START MATCH');
  start.addEventListener('click', () => { if (home.id !== away.id) onStart(home, away); });
  screen.appendChild(start);

  root.appendChild(screen);
  refresh();

  function podium(slot, label) {
    const wrap = el('div', `podium ${slot}`);
    const stage = el('div', 'podium-stage');
    const img = document.createElement('img');
    img.className = 'podium-player';
    const placeholder = el('div', 'podium-placeholder');
    stage.append(img, placeholder);
    const card = el('div', 'podium-card');
    const cardFlag = el('div', 'podium-flag');
    const col = el('div', 'podium-col');
    const lab = el('div', 'podium-label', label);
    const name = el('div', 'podium-name');
    col.append(lab, name);
    card.append(cardFlag, col);
    wrap.append(stage, card);
    wrap.addEventListener('click', () => { editing = slot; refresh(); });
    return { wrap, img, placeholder, card, cardFlag, lab, name };
  }

  function pick(c) {
    if (editing === 'home') {
      home = c;
      if (away.id === c.id) away = COUNTRIES.find((x) => x.id !== c.id) || away;
      editing = 'away';
    } else {
      away = c;
      if (home.id === c.id) home = COUNTRIES.find((x) => x.id !== c.id) || home;
    }
    refresh();
  }

  function fillPod(pod, c, label) {
    pod.lab.textContent = label;
    pod.name.textContent = c.name;
    pod.card.style.background = `linear-gradient(${hexA(c.primaryHex, 0.85)}, ${hexA(c.primaryHex, 0.5)})`;
    pod.cardFlag.innerHTML = '';
    pod.cardFlag.appendChild(flagImg(c, 24));
    const purl = playerURL(c);
    if (purl) { pod.img.src = purl; pod.img.style.display = 'block'; pod.placeholder.style.display = 'none'; }
    else {
      pod.img.style.display = 'none';
      pod.placeholder.style.display = 'flex';
      pod.placeholder.innerHTML = '';
      pod.placeholder.appendChild(flagImg(c, 80));
      pod.placeholder.appendChild(el('div', 'coming-soon', 'Player model coming soon'));
    }
  }

  function refresh() {
    fillPod(homePod, home, 'YOU');
    fillPod(awayPod, away, 'CPU');
    homePod.wrap.classList.toggle('active', editing === 'home');
    awayPod.wrap.classList.toggle('active', editing === 'away');
    const sel = editing === 'home' ? home : away;
    for (const cell of cells) {
      const on = cell._country.id === sel.id;
      cell.classList.toggle('selected', on);
      cell.style.borderColor = on ? cell._country.primaryHex : 'rgba(255,255,255,0.1)';
    }
    start.disabled = home.id === away.id;
    start.style.opacity = home.id === away.id ? '0.5' : '1';
  }

  return () => { root.innerHTML = ''; };
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

// "#rrggbb" + alpha → rgba()
function hexA(hex, a) {
  const s = hex.replace('#', '');
  const n = parseInt(s, 16);
  const r = (n >> 16) & 0xff, g = (n >> 8) & 0xff, b = n & 0xff;
  return `rgba(${r},${g},${b},${a})`;
}
