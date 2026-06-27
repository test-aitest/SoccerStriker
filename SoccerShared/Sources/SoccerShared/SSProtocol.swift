import Foundation

/// SoccerStriker のネットワークプロトコル定数。
/// Bonjour サービス型・プロトコルバージョン・JSON コーデックを集約する。
public enum SSProtocol {
    /// Bonjour サービス型。Mac が広告し iPhone が探索する。
    public static let serviceType = "_socstrk._udp"
    public static let version: UInt16 = 1

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = JSONDecoder()
}
