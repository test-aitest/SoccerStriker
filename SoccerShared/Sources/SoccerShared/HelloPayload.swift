import Foundation

/// 接続確立直後に双方が送る挨拶。役割とプロトコル版を相手に伝える。
public struct HelloPayload: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case mac          // ゲーム本体（Mac）
        case controller   // iPhone コントローラ（蹴り役）
    }

    public var role: Role
    public var protoVersion: UInt16
    public var tMono: UInt64

    public init(role: Role, protoVersion: UInt16, tMono: UInt64) {
        self.role = role
        self.protoVersion = protoVersion
        self.tMono = tMono
    }
}
