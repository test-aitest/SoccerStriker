import Foundation

/// ピッチ寸法・チーム編成・物理係数など、Mac と iPhone で共有したい定数。
/// 座標系は Three.js と揃える：x=横（右が+）, y=上, z=縦（相手ゴール方向が -z）。
public enum Pitch {
    /// ピッチ全長（z 方向, メートル）。4vs4 想定のミニコート。
    public static let length: Float = 42
    /// ピッチ全幅（x 方向, メートル）。
    public static let width: Float = 26
    /// ゴールの幅（x 方向）。
    public static let goalWidth: Float = 6
    /// ゴールの高さ（y 方向）。
    public static let goalHeight: Float = 2.4
    /// 自陣ゴールライン z（守るゴール）。
    public static let ownGoalZ: Float = length / 2
    /// 相手ゴールライン z（攻めるゴール）。
    public static let enemyGoalZ: Float = -length / 2
}

/// 4vs4：フィールドプレイヤー 4 名（うち 1 名は GK 兼務とせず、GK は別枠 1 名）。
/// Nintendo Switch Sports 準拠で「4vs4 = フィールド 4 名」とし、内部的に GK を追加。
public enum Roster {
    /// 各チームのフィールドプレイヤー数。
    public static let fieldPlayers = 4
    /// GK を含めた総数。
    public static let total = fieldPlayers + 1
}

/// ボール物理の係数（簡易）。
public enum BallPhysics {
    /// 地面摩擦による 1 秒あたりの減速率。
    public static let groundDamping: Float = 0.55
    /// 重力加速度。
    public static let gravity: Float = 9.8
    /// 反発係数（バウンド）。
    public static let restitution: Float = 0.55
    /// シュート最大初速 (m/s)（power=1.0 のとき）。
    public static let maxShotSpeed: Float = 24
    /// ボール半径。
    public static let radius: Float = 0.22
}
