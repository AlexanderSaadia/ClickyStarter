import Foundation

/// A Sendable JSON representation for the Codex protocol.
enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var array: [JSONValue] {
        if case .array(let values) = self { return values }
        return []
    }

    var object: [String: JSONValue] {
        if case .object(let values) = self { return values }
        return [:]
    }

    var integer: Int? {
        if case .number(let value) = self { return Int(exactly: value) }
        return nil
    }

    subscript(key: String) -> JSONValue {
        object[key] ?? .null
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
