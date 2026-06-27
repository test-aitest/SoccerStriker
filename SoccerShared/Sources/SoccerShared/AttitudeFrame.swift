import Foundation

/// iPhone の姿勢（クォータニオン）と角速度の大きさを 1 フレーム分運ぶ。
/// 主にデバッグ HUD と狙い方向のリアルタイム表示に使う。
public struct AttitudeFrame: Codable, Sendable, Equatable {
    public var seq: UInt32
    public var tMono: UInt64
    public var qw: Float
    public var qx: Float
    public var qy: Float
    public var qz: Float
    public var angSpeed: Float

    public init(
        seq: UInt32,
        tMono: UInt64,
        qw: Float,
        qx: Float,
        qy: Float,
        qz: Float,
        angSpeed: Float
    ) {
        self.seq = seq
        self.tMono = tMono
        self.qw = qw
        self.qx = qx
        self.qy = qy
        self.qz = qz
        self.angSpeed = angSpeed
    }
}
