import Foundation
import Combine

/// 已配对服务器列表（含配对码），持久化在钥匙串中。
final class ServerStore: ObservableObject {
    @Published private(set) var profiles: [ServerProfile] = []
    @Published var activeID: UUID?

    private let keychainKey = "servers.v1"
    private let activeDefaultsKey = "dsh.activeServer"

    init() {
        load()
        if let raw = UserDefaults.standard.string(forKey: activeDefaultsKey), let id = UUID(uuidString: raw) {
            activeID = profiles.contains(where: { $0.id == id }) ? id : nil
        }
    }

    var active: ServerProfile? {
        guard let id = activeID else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    func add(_ profile: ServerProfile) {
        if let index = profiles.firstIndex(where: { $0.baseURL == profile.baseURL }) {
            var updated = profile
            updated.id = profiles[index].id
            updated.lastUsed = Date()
            profiles[index] = updated
            persist()
            activate(updated.id)
            return
        }

        profiles.append(profile)
        persist()
        activate(profile.id)
    }

    func update(_ profile: ServerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persist()
    }

    func remove(_ id: UUID) {
        profiles.removeAll(where: { $0.id == id })
        persist()
        if activeID == id {
            deactivate()
        }
    }

    func activate(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        UserDefaults.standard.set(id.uuidString, forKey: activeDefaultsKey)
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].lastUsed = Date()
            persist()
        }
        Haptics.success()
    }

    func deactivate() {
        activeID = nil
        UserDefaults.standard.removeObject(forKey: activeDefaultsKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        KeychainStore.set(data, for: keychainKey)
    }

    private func load() {
        guard let data = KeychainStore.get(keychainKey),
              let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded.sorted { $0.lastUsed > $1.lastUsed }
    }
}
