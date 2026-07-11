import Foundation

/// A Sendable JSON value used at the app-server boundary. The bridge keeps
/// unknown fields as JSON instead of failing decoding when Codex adds fields.
enum AgentJSON: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([AgentJSON])
    case object([String: AgentJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AgentJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AgentJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    subscript(key: String) -> AgentJSON? {
        guard case let .object(object) = self else { return nil }
        return object[key]
    }

    var objectValue: [String: AgentJSON]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [AgentJSON]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var integerValue: Int64? {
        switch self {
        case let .integer(value): return value
        case let .number(value) where value.rounded() == value: return Int64(value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .integer(value): return Double(value)
        case let .number(value): return value
        default: return nil
        }
    }

    static let emptyObject: AgentJSON = .object([:])
}

enum AgentRequestID: Sendable, Hashable, Codable, CustomStringConvertible {
    case integer(Int64)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON-RPC request id must be an integer or string"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .integer(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }

    var description: String {
        switch self {
        case let .integer(value): String(value)
        case let .string(value): value
        }
    }
}

struct AgentRPCErrorPayload: Sendable, Equatable, Codable {
    let code: Int
    let message: String
    let data: AgentJSON?
}

/// JSON-RPC 2.0 envelope used by app-server. Codex intentionally omits the
/// `jsonrpc` member on the wire.
struct AgentRPCEnvelope: Sendable, Equatable, Codable {
    var id: AgentRequestID?
    var method: String?
    var params: AgentJSON?
    var result: AgentJSON?
    var error: AgentRPCErrorPayload?

    init(
        id: AgentRequestID? = nil,
        method: String? = nil,
        params: AgentJSON? = nil,
        result: AgentJSON? = nil,
        error: AgentRPCErrorPayload? = nil
    ) {
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }

    var jsonValue: AgentJSON {
        var object: [String: AgentJSON] = [:]
        if let id {
            switch id {
            case let .integer(value): object["id"] = .integer(value)
            case let .string(value): object["id"] = .string(value)
            }
        }
        if let method { object["method"] = .string(method) }
        if let params { object["params"] = params }
        if let result { object["result"] = result }
        if let error {
            var errorObject: [String: AgentJSON] = [
                "code": .integer(Int64(error.code)),
                "message": .string(error.message)
            ]
            if let data = error.data { errorObject["data"] = data }
            object["error"] = .object(errorObject)
        }
        return .object(object)
    }
}
