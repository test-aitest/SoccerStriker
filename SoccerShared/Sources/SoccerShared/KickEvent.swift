import Foundation

/// iPhone を振った瞬間に発火する「蹴り／ヘディング」イベント。
/// `KickDetector` が角速度ピークから生成し、Mac のゲームエンジンへ送る。
public struct KickEvent: Codable, Sendable, Equatable {
    /// 単調増加するイベント番号（重複排除用）。
    public var seq: UInt32
    /// 端末時刻（ns, 単調）。
    public var tMono: UInt64
    /// 蹴りの種類（iPhone 側で選択中のアクション）。
    public var kind: KickKind
    /// シュート/パスの強さ 0…1（角速度ピークを正規化）。
    public var power: Float
    /// 横方向の狙い -1（左）… +1（右）。端末のヨー/ロールから算出。
    public var aim: Float
    /// 浮かせ具合 0（グラウンダー）… 1（ループ/ヘディング）。
    public var loft: Float

    public init(
        seq: UInt32,
        tMono: UInt64,
        kind: KickKind,
        power: Float,
        aim: Float,
        loft: Float
    ) {
        self.seq = seq
        self.tMono = tMono
        self.kind = kind
        self.power = power
        self.aim = aim
        self.loft = loft
    }
}

/// 蹴りの種類。iPhone のアクション切替に対応（3 種）。
public enum KickKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case shoot         // ゴールへ強く蹴る
    case dribble       // ボールを前方へ小さく運ぶ
    case divingHeader  // 浮き球に飛び込むヘディング

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .shoot:        return "シュート"
        case .dribble:      return "ドリブル"
        case .divingHeader: return "ダイビングヘッド"
        }
    }
}
