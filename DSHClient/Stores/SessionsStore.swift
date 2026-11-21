import Foundation
import Combine

/// 会话列表：合并电脑端 ACP 会话与手机本地记录。
final class SessionsStore: ObservableObject {
    @Published var sessions: [SessionSummary] = []
    @Published var workspaces: [Workspace] = []
    @Published var loading = false
    @Published var error: String?
    @Published var dshState = "unknown"
    @Published var serverName = ""
    @Published var bridgeVersion = ""
    @Published var autoApprove = false

    private let api: APIClient
    private let transcripts = TranscriptStore.shared

    init(server: ServerProfile) {
        self.api = APIClient(baseURL: server.url, token: server.token)
    }

    func refresh() {
        loading = true
        error = nil

        api.get("/v1/server") { [weak self] (result: Result<ServerInfoResponse, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success(let info):
                self.serverName = info.name
                self.bridgeVersion = info.bridge
                self.workspaces = info.workspaces
                self.dshState = info.dsh.state
                self.autoApprove = info.autoApprove ?? false
                if let detail = info.dsh.error, info.dsh.state != "ready" {
                    self.error = detail
                }
            case .failure(let failure):
                self.dshState = "unreachable"
                self.error = failure.localizedDescription
            }
            self.loadSessions()
        }
    }

    private func loadSessions() {
        api.get("/v1/sessions") { [weak self] (result: Result<SessionsResponse, APIError>) in
            guard let self = self else { return }
            self.loading = false

            switch result {
            case .success(let response):
                var merged = response.sessions
                let remoteIDs = Set(merged.map { $0.id })
                for local in self.transcripts.allSessions() where !remoteIDs.contains(local.id) {
                    var copy = local
                    copy.live = false
                    merged.append(copy)
                }
                self.sessions = merged.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
            case .failure(let failure):
                if self.error == nil {
                    self.error = failure.localizedDescription
                }
                self.sessions = self.transcripts.allSessions().sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
            }
        }
    }

    func createSession(workspace: Workspace, completion: @escaping (SessionSummary?) -> Void) {
        loading = true
        api.post("/v1/sessions", body: ["cwd": workspace.path, "title": "新会话"]) { [weak self] (result: Result<CreateSessionResponse, APIError>) in
            guard let self = self else { return }
            self.loading = false
            switch result {
            case .success(let response):
                if !self.sessions.contains(where: { $0.id == response.session.id }) {
                    self.sessions.insert(response.session, at: 0)
                }
                completion(response.session)
            case .failure(let failure):
                self.error = failure.localizedDescription
                completion(nil)
            }
        }
    }

    func closeSession(_ session: SessionSummary, completion: @escaping () -> Void = {}) {
        api.post("/v1/sessions/\(session.id)/close", body: [:]) { [weak self] (_: Result<SimpleResponse, APIError>) in
            self?.refresh()
            completion()
        }
    }
}
