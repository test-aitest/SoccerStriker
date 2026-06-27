# Soccer Striker ⚽️

Nintendo Switch Sports の「サッカー」を参考にした **4vs4 サッカー** ゲーム。
**Mac がゲーム画面**、**iPhone を振って蹴るコントローラ**になる（HomeRunDerby と同じ構成）。

```
┌─────────────────┐   Bonjour/UDP P2P   ┌────────────────────┐
│ SoccerStrikerKick│ ──────────────────▶ │ SoccerStrikerMac    │
│ (iPhone=蹴り役)   │  KickEvent          │ (Mac=ゲーム本体)      │
│ CMMotionManager  │ ◀────────────────── │ NetworkServer       │
│ →KickDetector    │  GoalEvent(振動)     │ →GameModel(60Hz)    │
└─────────────────┘                      │ →SoccerEngine 4v4   │
        共有: SoccerShared                  │ →WebSceneKit(Three) │
                                          └────────────────────┘
```

## 構成

| ターゲット / パッケージ | 役割 |
|----------------------|------|
| `SoccerShared` | プロトコル・モーションイベント型・**KickDetector**・**SoccerEngine(4v4物理+AI)**。純Swiftでテスト済み |
| `SoccerStrikerMac` | ゲーム本体。`NetworkServer`/`GameModel`/`MatchView`。Three.js を WebSceneKit で描画 |
| `SoccerStrikerKick` | iPhone コントローラ。`MotionStreamer`/`NetworkClient`/`HapticsPlayer` |
| `Packages/WebSceneKit` | WKWebView で Three.js を動かす汎用パッケージ（HomeRunDerby から流用） |
| `WebSource/pitch.js` | ピッチ・ゴール・選手・ボールの 3D 描画 |

## セットアップ

```bash
# 1. Web バンドルを生成（WebSource → Mac の Resources/web）
npm install
npm run build          # 変更監視は npm run watch

# 2. Xcode プロジェクト生成
xcodegen generate

# 3. 起動
open SoccerStriker.xcodeproj   # Mac スキームで実行
```

iPhone 側（`SoccerStrikerKick`）を実機にインストールして起動すると、同一 Wi-Fi
（または P2P/AWDL）上の Mac を自動で見つけて接続する。

## ゲーム性（AI vs AI ＋ 人間の決定的介入）

[Pirhan/soccer-game-ai](https://github.com/Pirhan/soccer-game-ai) のように **両チームをルールベース AI が自動で操作**して試合が進む。
プレイヤーは常時操作するのではなく、**勝負どころで iPhone を振って介入**する：

- **シュートチャンス（攻撃）**: 自チームがゴール前に持ち込むと時間が止まりゲージ出現 → 成功で **100% ゴール**
- **セーブチャンス（守備）**: 相手の枠内シュートが来ると時間が止まりゲージ出現 → 成功で **防ぐ**、失敗で失点

ゲージはチャンスごとに 2 種が交互に出る：
- **タイミング型**: 左右に動くマーカーを中央の「当たりゾーン」で振る
- **連打パワー型**: 制限時間内に振りまくってバーを規定ラインまで溜める

## 操作

- **iPhone**: チャンス/ピンチでゲージが出たら **端末を振る**（タイミングよく／連打で）。
- **キーボード（iPhone なしの動作確認用）**: `Space`=振る / `Esc`=タイトル。

## いま動くもの

- 4vs4（各 GK1+フィールド4）の **両チーム AI 自動進行**（パス/シュート/ドリブル判断、フォーメーション維持）
- **立体的な 3D 選手モデル**（走りアニメ・向き・操作リング）、観客スタンド、ネット付きゴール
- **チャンス/ピンチのゲージ介入**（タイミング型・連打パワー型）、成功=100%ゴール/セーブ
- 得点・チャンス時に iPhone へ振動フィードバック
- `SoccerEngine` は純 Swift・**14 UnitTest 合格**（AI が実際にチャンスを生むことも検証）

## 今後のロードマップ

1. **glTF 選手モデル**＋本物の走り/蹴り/ダイビングモーション（`WebSceneAssetRouter` 利用）
2. **演出**: ボール追従カメラ、ゴールネット揺れ、リプレイ、効果音（キック/歓声/ホイッスル）
3. **AI 高度化**: マーク、スペースへの走り込み、難易度調整
4. **試合フロー**: 前後半・時間・スコアボード演出
5. **チャンス種類の拡張**: ダイビングヘッド専用チャンス、PK 等
