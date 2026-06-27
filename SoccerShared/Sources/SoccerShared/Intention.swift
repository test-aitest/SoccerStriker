import Foundation

/// AI エージェント（Gemini）が各選手に与える「意図」。
/// エンジンはこれを実行するだけ（判断は AI 側）。AI 応答が来るまでは
/// 直前の意図を保持し、何も無ければルールのフォーメーションにフォールバックする。
public struct Intention: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable {
        case move      // ターゲット地点へ走る
        case dribble   // ボールを持って相手ゴールへ運ぶ
        case shoot     // シュート
        case pass      // 味方へパス
        case mark      // ターゲット（相手）をマーク
        case support   // ターゲット周辺でパスを受ける動き
        case hold      // その場を保持
    }

    public var playerID: Int
    public var action: Action
    /// ピッチ座標（x=横, z=縦）。move/mark/support の移動先。
    public var targetX: Float
    public var targetZ: Float
    /// pass の宛先選手 id（action == .pass のときのみ有効）。
    public var passTo: Int?

    public init(playerID: Int, action: Action, targetX: Float, targetZ: Float, passTo: Int? = nil) {
        self.playerID = playerID
        self.action = action
        self.targetX = targetX
        self.targetZ = targetZ
        self.passTo = passTo
    }

    public var target: SIMD2<Float> { SIMD2(targetX, targetZ) }
}
