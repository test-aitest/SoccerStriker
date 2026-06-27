import Foundation

/// Mac → iPhone のフィードバック。得点/被弾/ボールタッチ時に
/// iPhone を振動させ、スコアを通知する。
public struct GoalEvent: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable {
        case goal       // 自チーム得点
        case conceded   // 失点
        case save       // GK セーブされた
        case touch      // ボールに触れた（軽い振動）
        case miss       // 枠外
    }

    public var outcome: Outcome
    /// 演出の強さ 0…1（ハプティクス強度）。
    public var intensity: Float
    public var teamScore: Int
    public var opponentScore: Int

    public init(
        outcome: Outcome,
        intensity: Float,
        teamScore: Int,
        opponentScore: Int
    ) {
        self.outcome = outcome
        self.intensity = intensity
        self.teamScore = teamScore
        self.opponentScore = opponentScore
    }
}
