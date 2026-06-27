// Country.swift の移植：代表チーム（国）のデータ。
// flagAsset があれば assets/flags/<id>.svg、playerAsset があれば assets/teams/<asset>*.png。

export const COUNTRIES = [
  { id: 'jp', name: 'Japan', flag: '🇯🇵', primaryHex: '#1b3aa0', secondaryHex: '#ffffff', flagAsset: 'jp', playerAsset: 'jp' },
  { id: 'ar', name: 'Argentina', flag: '🇦🇷', primaryHex: '#6cace4', secondaryHex: '#ffffff', flagAsset: 'ar', playerAsset: null },
  { id: 'br', name: 'Brazil', flag: '🇧🇷', primaryHex: '#ffdf00', secondaryHex: '#2952c8', flagAsset: 'br', playerAsset: 'br' },
  { id: 'es', name: 'Spain', flag: '🇪🇸', primaryHex: '#c60b1e', secondaryHex: '#ffc400', flagAsset: 'es', playerAsset: null },
  { id: 'kr', name: 'Korea', flag: '🇰🇷', primaryHex: '#c8102e', secondaryHex: '#ffffff', flagAsset: 'kr', playerAsset: null },
  { id: 'us', name: 'USA', flag: '🇺🇸', primaryHex: '#0a3161', secondaryHex: '#b31942', flagAsset: 'us', playerAsset: null },
];

export const byId = (id) => COUNTRIES.find((c) => c.id === id);
export const JAPAN = COUNTRIES[0];
export const BRAZIL = COUNTRIES[2];

// アセットURLヘルパ。
export const flagURL = (c) => (c.flagAsset ? `./assets/flags/${c.flagAsset}.svg` : null);
export const playerURL = (c) => (c.playerAsset ? `./assets/teams/${c.playerAsset}.png` : null);
export const poseURL = (c, pose) => (c.playerAsset ? `./assets/teams/${c.playerAsset}_${pose}.png` : null);

// 国旗を <img> か絵文字で表示する小ヘルパ。
export function flagImg(c, height = 28) {
  const url = flagURL(c);
  if (url) {
    const img = document.createElement('img');
    img.src = url;
    img.alt = c.name;
    img.style.height = `${height}px`;
    img.style.borderRadius = '3px';
    img.style.boxShadow = 'inset 0 0 0 0.5px rgba(255,255,255,0.15)';
    return img;
  }
  const span = document.createElement('span');
  span.textContent = c.flag;
  span.style.fontSize = `${height * 0.9}px`;
  return span;
}
