import SwiftUI

struct RootView: View {
    @EnvironmentObject private var servers: ServerStore

    var body: some View {
        Group {
            if let active = servers.active {
                MainView(server: active)
                    .id(active.baseURL + active.token)
            } else {
                OnboardingView()
            }
        }
        .accentColor(Theme.accent)
    }
}

struct MainView: View {
    let server: ServerProfile
    @StateObject private var store: SessionsStore

    init(server: ServerProfile) {
        self.server = server
        _store = StateObject(wrappedValue: SessionsStore(server: server))
    }

    var body: some View {
        NavigationView {
            SessionsView(server: server)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(store)
    }
}
