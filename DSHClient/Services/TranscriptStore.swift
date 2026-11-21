import Foundation

/// 手机本地保存的对话记录（桥接服务的 ACP 接口不回放历史）。
final class TranscriptStore {
    static let shared = TranscriptStore()

    struct Stored: Codable {
        var session: SessionSummary
        var messages: [ChatMessage]
        var savedAt: Date
    }

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("DSHClient/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load(sessionId: String) -> Stored? {
        guard let data = try? Data(contentsOf: fileURL(for: sessionId)) else { return nil }
        return try? decoder.decode(Stored.self, from: data)
    }

    func save(_ stored: Stored) {
        guard let data = try? encoder.encode(stored) else { return }
        try? data.write(to: fileURL(for: stored.session.id), options: .atomic)
    }

    func allSessions() -> [SessionSummary] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) else {
            return []
        }
        var sessions: [SessionSummary] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let stored = try? decoder.decode(Stored.self, from: data) else { continue }
            sessions.append(stored.session)
        }
        return sessions.sorted { lhs, rhs in
            (lhs.updatedAt ?? "") > (rhs.updatedAt ?? "")
        }
    }

    func delete(sessionId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: sessionId))
    }

    func deleteAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func fileURL(for sessionId: String) -> URL {
        directory.appendingPathComponent(Self.safeName(sessionId) + ".json")
    }

    private static func safeName(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let name = String(scalars)
        return name.isEmpty ? "session" : name
    }
}
