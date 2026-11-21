import SwiftUI

@main
struct DSHClientApp: App {
    @StateObject private var servers = ServerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(servers)
        }
    }
}
