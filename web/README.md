# Soccer Striker — Web 版 ⚽️

macOS 版 Soccer Striker（Mac=ゲーム画面／iPhone=振るコントローラ）を、**ブラウザだけで完結する Web アプリ**に移植したもの。iPhone は不要で、**キーボード**でチャンスに介入する。

- 3D 描画：Three.js（`vendor/three.module.js` を同梱）
- ゲームロジック：`SoccerEngine`/`GameModel` を JavaScript へ移植（純ロジック）
- AI：エンジン内蔵の**ルールベース AI**（両チーム自動進行）。※元 Mac 版の Gemini 連携はブラウザでは API キーが露出するため未採用

## 起動

ES モジュールを使うため、ファイルを直接開く（file://）のではなく**ローカルサーバ**で配信する：

```bash
cd web
python3 -m http.server 8000
# → ブラウザで http://localhost:8000/ を開く
```

`npx serve` など他の静的サーバでも可。

## 操作

- **タイトル**：`KICK OFF` →（国選択）→ `START MATCH`
- **試合中**：両チームは AI が自動でプレイ。要所でゲージが出たら介入する。
  - **連打パワー型**：`↑`キー（または `Space`／方向キー）を**素早く連打**してバーを溜める
  - **タイミング型**：マーカーが緑の当たりゾーンに来た瞬間に**1 回押す**
  - `Esc`：タイトルへ戻る

## 構成

| ファイル | 役割 | 移植元 |
|---|---|---|
| `src/engine.js` | 4v4 物理 + ルールベース AI | `SoccerShared/SoccerEngine.swift` |
| `src/game.js` | 試合ループ・チャンス/ゲージ判定 | `SoccerStrikerMac/Game/GameModel.swift` |
| `src/render.js` | Three.js ピッチ描画 | `WebSource/pitch.js` |
| `src/hud.js` | スコアボード・ゲージ・カットイン | `Game/MatchView.swift` |
| `src/screens.js` | タイトル・国選択画面 | `App/RootView.swift`, `App/CountrySelectView.swift` |
| `src/input.js` | キーボード入力（振りの代替） | `MatchView.handleKey` |
| `src/audio.js` | 効果音（WebAudio 合成 + mp3） | `Audio/AudioFX.swift` |
| `src/countries.js` | 代表チームデータ | `Domain/Country.swift` |
| `src/constants.js` / `src/vec.js` | 定数・ベクトル演算 | `GameConstants.swift` / `simd` |

`assets/`（flags・teams・audio）は macOS 版 `Resources` からコピー。
