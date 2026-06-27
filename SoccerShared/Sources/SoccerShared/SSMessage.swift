import Foundation

/// iPhone ↔ Mac で UDP 上をやり取りする全メッセージ。
/// JSON エンコードして `NWConnection` で送受信する。
public enum SSMessage: Codable, Sendable, Equatable {
    case hello(HelloPayload)
    case attitude(AttitudeFrame)
    case kick(KickEvent)
    case goal(GoalEvent)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum Kind: String, Codable {
        case hello
        case attitude
        case kick
        case goal
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .hello:
            self = .hello(try c.decode(HelloPayload.self, forKey: .payload))
        case .attitude:
            self = .attitude(try c.decode(AttitudeFrame.self, forKey: .payload))
        case .kick:
            self = .kick(try c.decode(KickEvent.self, forKey: .payload))
        case .goal:
            self = .goal(try c.decode(GoalEvent.self, forKey: .payload))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let v):
            try c.encode(Kind.hello, forKey: .type)
            try c.encode(v, forKey: .payload)
        case .attitude(let v):
            try c.encode(Kind.attitude, forKey: .type)
            try c.encode(v, forKey: .payload)
        case .kick(let v):
            try c.encode(Kind.kick, forKey: .type)
            try c.encode(v, forKey: .payload)
        case .goal(let v):
            try c.encode(Kind.goal, forKey: .type)
            try c.encode(v, forKey: .payload)
        }
    }
}

extension SSMessage {
    public func encoded() throws -> Data {
        try SSProtocol.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SSMessage {
        try SSProtocol.decoder.decode(SSMessage.self, from: data)
    }
}
