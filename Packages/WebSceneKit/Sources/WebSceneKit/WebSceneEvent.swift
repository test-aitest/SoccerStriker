import Foundation

public struct WebSceneEvent: Sendable {
    public let type: String
    public let payload: [String: WebSceneValue]
    public let receivedAt: Date

    public init(type: String, payload: [String: WebSceneValue], receivedAt: Date = Date()) {
        self.type = type
        self.payload = payload
        self.receivedAt = receivedAt
    }
}

public enum WebSceneValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([WebSceneValue])
    case object([String: WebSceneValue])
    case null

    public var string: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var number: Double? {
        if case .number(let v) = self { return v }
        return nil
    }

    public var int: Int? {
        number.map { Int($0) }
    }

    public var bool: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    public var array: [WebSceneValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    public var object: [String: WebSceneValue]? {
        if case .object(let v) = self { return v }
        return nil
    }
}

extension WebSceneValue {
    static func from(_ any: Any?) -> WebSceneValue {
        guard let any else { return .null }
        if any is NSNull { return .null }
        if let v = any as? String { return .string(v) }
        if let v = any as? Bool { return .bool(v) }
        if let v = any as? NSNumber {
            let type = String(cString: v.objCType)
            if type == "c" || type == "B" {
                return .bool(v.boolValue)
            }
            return .number(v.doubleValue)
        }
        if let v = any as? [Any] { return .array(v.map { WebSceneValue.from($0) }) }
        if let v = any as? [String: Any] {
            var out: [String: WebSceneValue] = [:]
            for (k, val) in v { out[k] = WebSceneValue.from(val) }
            return .object(out)
        }
        return .null
    }
}
