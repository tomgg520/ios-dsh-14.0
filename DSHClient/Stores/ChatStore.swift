import Foundation
import Combine

/// 单个会话的聊天状态：发送、流式增量、工具调用、授权请求、本地持久化。
final class ChatStore: ObservableObject {
    let session: SessionSummary

    @Published var messages: [ChatMessage] = []
    @Published var title: String
    @Published var isStreaming = false
    @Published var isCancelling = false
    @Published var connected = false
    @Published var dshState = "unknown"
    @Published var statusDetail: String?
    @Published var banner: String?
    @Published var permission: PermissionRequest?
    @Published var configOptions: [ConfigOption] = []
    @Published var usageText: String?
    @Published var scrollTick = 0
    @Published var authFailed = false

    private let api: APIClient
    private let sse: SSEClient
    private let transcripts = TranscriptStore.shared

    private var assistantIndex: Int?
    private var turnId: String?

    init(session: SessionSummary, server: ServerProfile) {
        self.session = session
        self.title = session.displayTitle
        self.api = APIClient(baseURL: server.url, token: server.token)
        self.sse = SSEClient(url: server.url.appendingPathComponent("v1/events"), token: server.token)

        if let stored = transcripts.load(sessionId: session.id) {
            self.messages = stored.messages.map { message in
                var copy = message
                copy.isStreaming = false
                return copy
            }
        }

        sse.onEvent = { [weak self] json in
            self?.handle(json)
        }
        sse.onConnectionChange = { [weak self] up in
            self?.connected = up
            if up {
                self?.statusDetail = nil
            } else if self?.authFailed != true {
                self?.statusDetail = "连接已断开，正在重连…"
            }
        }
        sse.onAuthFailure = { [weak self] in
            self?.authFailed = true
            self?.statusDetail = "配对码已失效，请到设置里重新配对"
        }
    }

    deinit {
        sse.disconnect()
    }

    // MARK: - 生命周期

    func start() {
        sse.connect()
        resume()
    }

    func stop() {
        sse.disconnect()
        save()
    }

    private var pathID: String {
        session.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session.id
    }

    private func resume() {
        api.post("/v1/sessions/\(pathID)/resume", body: [:]) { [weak self] (result: Result<ConfigResponse, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if !response.config.isEmpty {
                    self.configOptions = response.config
                }
                self.banner = nil
            case .failure(let failure):
                self.banner = failure.localizedDescription
            }
        }
    }

    func retry() {
        authFailed = false
        sse.disconnect()
        sse.connect()
        resume()
    }

    // MARK: - 发送

    func send(_ raw: String) {
        let text = raw.trimmed
        guard !text.isEmpty, !isStreaming else { return }

        Haptics.light()
        banner = nil
        permission = nil

        messages.append(ChatMessage(role: .user, text: text))
        startAssistant()
        isStreaming = true
        isCancelling = false
        scrollTick += 1

        api.post("/v1/sessions/\(pathID)/prompt", body: ["text": text]) { [weak self] (result: Result<PromptResponse, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                self.turnId = response.turnId
            case .failure(let failure):
                if self.isStreaming {
                    self.finishTurn(stopReason: "error", error: failure.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        guard isStreaming, !isCancelling else { return }
        isCancelling = true
        Haptics.medium()
        api.post("/v1/sessions/\(pathID)/cancel", body: [:]) { [weak self] (result: Result<SimpleResponse, APIError>) in
            guard let self = self else { return }
            if case .failure(let failure) = result {
                self.isCancelling = false
                self.banner = failure.localizedDescription
            }
        }
    }

    func answer(permission request: PermissionRequest, optionId: String?) {
        var body: [String: Any] = [:]
        if let optionId = optionId {
            body["optionId"] = optionId
        }
        api.post("/v1/permissions/\(request.id)", body: body) { [weak self] (result: Result<SimpleResponse, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success:
                if self.permission?.id == request.id {
                    self.permission = nil
                }
                self.appendSystem(optionId == nil ? "已拒绝本次操作" : "已允许本次操作")
            case .failure(let failure):
                self.banner = failure.localizedDescription
            }
        }
    }

    func select(configId: String, value: String) {
        if let index = configOptions.firstIndex(where: { $0.id == configId }) {
            configOptions[index].currentValue = .string(value)
        }
        api.post("/v1/sessions/\(pathID)/config", body: ["configId": configId, "value": value]) { [weak self] (result: Result<ConfigResponse, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if !response.config.isEmpty {
                    self.configOptions = response.config
                }
            case .failure(let failure):
                self.banner = failure.localizedDescription
                self.resume()
            }
        }
    }

    func clearLocal() {
        messages = []
        transcripts.delete(sessionId: session.id)
    }

    func closeSession(completion: @escaping () -> Void = {}) {
        api.post("/v1/sessions/\(pathID)/close", body: [:]) { (_: Result<SimpleResponse, APIError>) in
            completion()
        }
    }

    // MARK: - 事件

    private func handle(_ json: [String: Any]) {
        let event = ChatEvent(json: json)

        if let sessionId = event.sessionId, sessionId != session.id {
            return
        }

        switch event.type {
        case "hello":
            dshState = event.string("dsh") ?? dshState
            if configOptions.isEmpty {
                resume()
            }
        case "state":
            if let state = event.string("dsh") {
                dshState = state
                if state == "ready" {
                    banner = nil
                    if configOptions.isEmpty {
                        resume()
                    }
                }
            }
            if let detail = event.string("detail"), dshState != "ready" {
                statusDetail = detail
            }
        case "text":
            if let text = event.string("text"), !text.isEmpty {
                let index = ensureAssistant()
                messages[index].text += text
                messages[index].isStreaming = true
                scrollTick += 1
            }
        case "thought":
            if let text = event.string("text"), !text.isEmpty {
                let index = ensureAssistant()
                messages[index].thinking += text
                messages[index].isStreaming = true
                scrollTick += 1
            }
        case "tool":
            handleTool(event)
        case "turn_ended":
            finishTurn(stopReason: event.string("stopReason") ?? "end_turn", error: event.string("error"))
        case "permission":
            handlePermission(event)
        case "permission_resolved":
            if let permissionId = event.string("permissionId"), permission?.id == permissionId {
                permission = nil
            }
        case "config":
            if let config = event.decode([ConfigOption].self, key: "config"), !config.isEmpty {
                configOptions = config
            }
        case "usage":
            if let used = event.int("used"), let size = event.int("size") {
                usageText = "\(TimeFormat.tokens(used)) / \(TimeFormat.tokens(size))"
            }
        case "title":
            if let newTitle = event.string("title"), !newTitle.isEmpty {
                title = newTitle
            }
        case "error":
            banner = event.string("message")
        default:
            break
        }
    }

    private func handleTool(_ event: ChatEvent) {
        guard let tool = event.dict("tool"), let id = tool["id"] as? String else { return }

        let title = tool["title"] as? String
        let kind = tool["kind"] as? String
        let status = tool["status"] as? String
        let detail = tool["detail"] as? String

        let index = ensureAssistant()

        if let toolIndex = messages[index].tools.firstIndex(where: { $0.id == id }) {
            var updated = messages[index].tools[toolIndex]
            if let value = title, !value.isEmpty { updated.title = value }
            if let value = kind, !value.isEmpty { updated.kind = value }
            if let value = status, !value.isEmpty { updated.status = value }
            if let value = detail, !value.isEmpty { updated.detail = value }
            messages[index].tools[toolIndex] = updated
        } else {
            messages[index].tools.append(ToolCallModel(
                id: id,
                title: title ?? "工具调用",
                kind: kind ?? "other",
                status: status ?? "pending",
                detail: detail ?? ""
            ))
        }
        scrollTick += 1
    }

    private func handlePermission(_ event: ChatEvent) {
        guard let payload = event.dict("permission"), let id = payload["id"] as? String else { return }

        var options: [PermissionOption] = []
        if let rawOptions = payload["options"] as? [[String: Any]] {
            for raw in rawOptions {
                guard let optionId = raw["id"] as? String else { continue }
                options.append(PermissionOption(
                    id: optionId,
                    name: raw["name"] as? String ?? optionId,
                    kind: raw["kind"] as? String ?? ""
                ))
            }
        }

        permission = PermissionRequest(
            id: id,
            sessionId: event.sessionId ?? session.id,
            title: payload["title"] as? String ?? "需要授权",
            detail: payload["detail"] as? String ?? "",
            options: options
        )
        Haptics.medium()
    }

    // MARK: - 内部

    private func startAssistant() {
        let message = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(message)
        assistantIndex = messages.count - 1
    }

    @discardableResult
    private func ensureAssistant() -> Int {
        if let index = assistantIndex, index < messages.count {
            return index
        }
        let message = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(message)
        assistantIndex = messages.count - 1
        return assistantIndex ?? (messages.count - 1)
    }

    private func finishTurn(stopReason: String, error: String?) {
        guard isStreaming || error != nil else { return }

        isStreaming = false
        isCancelling = false
        turnId = nil

        if let index = assistantIndex, index < messages.count {
            messages[index].isStreaming = false
            if stopReason == "refusal" && messages[index].text.isEmpty {
                messages[index].text = "（模型拒绝继续处理这条消息）"
            }
        }
        assistantIndex = nil

        if let error = error, !error.isEmpty {
            banner = error
            appendSystem("发生错误：\(error)", isError: true)
        } else if stopReason == "cancelled" {
            appendSystem("已停止生成")
        } else if stopReason == "max_tokens" {
            appendSystem("已达到本轮输出上限")
        }

        save()
        scrollTick += 1
    }

    private func appendSystem(_ text: String, isError: Bool = false) {
        messages.append(ChatMessage(role: .system, text: text, isError: isError))
        scrollTick += 1
    }

    private func save() {
        var summary = session
        summary.title = title
        summary.updatedAt = TimeFormat.isoNow()
        transcripts.save(TranscriptStore.Stored(session: summary, messages: messages, savedAt: Date()))
    }
}
