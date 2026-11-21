import Foundation

// MARK: - 服务器

struct ServerProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var token: String
    var lastUsed: Date

    init(id: UUID = UUID(), name: String, baseURL: String, token: String, lastUsed: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.token = token
        self.lastUsed = lastUsed
    }

    var url: URL {
        URL(string: baseURL) ?? URL(string: "http://127.0.0.1:8787")!
    }
}

struct Workspace: Codable, Identifiable, Hashable {
    var name: String
    var path: String
    var id: String { path }
}

// MARK: - 会话

struct SessionSummary: Codable, Identifiable, Hashable {
    var id: String
    var cwd: String
    var title: String
    var updatedAt: String?
    var live: Bool?

    var isLive: Bool { live == true }
    var displayTitle: String { title.isEmpty ? "新会话" : title }
    var displayFolder: String {
        guard !cwd.isEmpty else { return "" }
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        return (trimmed as NSString).lastPathComponent
    }
}

// MARK: - 配置项（模型 / 推理强度）

enum ConfigValue: Codable, Equatable {
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        self = .string("")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    var stringValue: String {
        if case .string(let value) = self { return value }
        return ""
    }
}

struct ConfigChoice: Codable, Identifiable, Equatable {
    var value: String
    var name: String
    var description: String?
    var group: String?

    var id: String { value }
}

struct ConfigChoiceGroup: Codable {
    var group: String?
    var name: String?
    var options: [ConfigChoice]
}

struct ConfigOption: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String?
    var type: String
    var currentValue: ConfigValue
    var choices: [ConfigChoice]

    enum CodingKeys: String, CodingKey {
        case id, name, category, type, currentValue, options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? id
        category = try? container.decodeIfPresent(String.self, forKey: .category)
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "select"
        currentValue = (try? container.decodeIfPresent(ConfigValue.self, forKey: .currentValue)) ?? .string("")

        var decoded: [ConfigChoice] = []
        if let groups = try? container.decodeIfPresent([ConfigChoiceGroup].self, forKey: .options) {
            for group in groups {
                for var choice in group.options {
                    choice.group = group.name ?? group.group
                    decoded.append(choice)
                }
            }
        } else if let flat = try? container.decodeIfPresent([ConfigChoice].self, forKey: .options) {
            decoded = flat
        }
        choices = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(type, forKey: .type)
        try container.encode(currentValue, forKey: .currentValue)
        try container.encode(choices, forKey: .options)
    }

    var selectedName: String {
        choices.first(where: { $0.value == currentValue.stringValue })?.name ?? currentValue.stringValue
    }
}

// MARK: - 消息

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ToolCallModel: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var kind: String
    var status: String
    var detail: String
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String
    var role: ChatRole
    var text: String
    var thinking: String
    var tools: [ToolCallModel]
    var createdAt: Date
    var isError: Bool
    var isStreaming: Bool

    init(id: String = UUID().uuidString,
         role: ChatRole,
         text: String = "",
         thinking: String = "",
         tools: [ToolCallModel] = [],
         createdAt: Date = Date(),
         isError: Bool = false,
         isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.thinking = thinking
        self.tools = tools
        self.createdAt = createdAt
        self.isError = isError
        self.isStreaming = isStreaming
    }
}

// MARK: - 授权

struct PermissionOption: Identifiable, Equatable {
    var id: String
    var name: String
    var kind: String

    var isAllow: Bool { kind.contains("allow") }
    var isReject: Bool { kind.contains("reject") || kind.contains("deny") }
}

struct PermissionRequest: Identifiable, Equatable {
    var id: String
    var sessionId: String
    var title: String
    var detail: String
    var options: [PermissionOption]
}

// MARK: - 接口响应

struct DshStatus: Codable {
    var state: String
    var error: String?
}

struct ServerInfoResponse: Codable {
    var ok: Bool
    var name: String
    var platform: String
    var bridge: String
    var workspaces: [Workspace]
    var autoApprove: Bool?
    var dsh: DshStatus
}

struct SessionsResponse: Codable {
    var sessions: [SessionSummary]
}

struct CreateSessionResponse: Codable {
    var session: SessionSummary
    var config: [ConfigOption]?
}

struct PromptResponse: Codable {
    var turnId: String
}

struct ConfigResponse: Codable {
    var config: [ConfigOption]
}

struct SimpleResponse: Codable {
    var ok: Bool?
}

struct ErrorBody: Codable {
    var code: String?
    var message: String?
}

struct ErrorEnvelope: Codable {
    var ok: Bool?
    var error: ErrorBody?
}

// MARK: - SSE 事件（宽松解析）

struct ChatEvent {
    var json: [String: Any]

    var type: String { json["type"] as? String ?? "" }
    var sessionId: String? { json["sessionId"] as? String }

    func string(_ key: String) -> String? {
        if let value = json[key] as? String { return value }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = json[key] as? Int { return value }
        if let value = json[key] as? NSNumber { return value.intValue }
        return nil
    }

    func dict(_ key: String) -> [String: Any]? { json[key] as? [String: Any] }

    func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let value = json[key], JSONSerialization.isValidJSONObject(value) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
