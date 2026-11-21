import SwiftUI

struct SessionsView: View {
    let server: ServerProfile

    @EnvironmentObject private var store: SessionsStore
    @EnvironmentObject private var servers: ServerStore

    private enum ActiveSheet: String, Identifiable {
        case picker
        case settings

        var id: String { rawValue }
    }

    @State private var sheet: ActiveSheet?
    @State private var created: SessionSummary?

    var body: some View {
        List {
            if let error = store.error {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.danger)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section(header: HStack(spacing: 8) {
                Text(store.serverName.isEmpty ? "会话" : store.serverName)
                Spacer()
                StatusDot(state: store.dshState)
            }) {
                ForEach(store.sessions) { session in
                    NavigationLink(destination: ChatView(session: session, server: server)) {
                        SessionRow(session: session)
                    }
                }

                if store.sessions.isEmpty {
                    if store.loading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在加载会话…")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: "还没有会话",
                            message: "点右上角的 + 新建会话，选择电脑上的工作目录。"
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }

            Section {
                Text("会话运行在电脑上。手机断线后重新打开仍可继续，但历史消息只保存在这台 iPhone。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("会话")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 6) {
                    StatusDot(state: store.dshState)
                    Text("DSH")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { sheet = .picker }) {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("刷新") { store.refresh() }
                    Button("设置") { sheet = .settings }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear { store.refresh() }
        .background(
            NavigationLink(
                destination: Group {
                    if let session = created {
                        ChatView(session: session, server: server)
                    } else {
                        EmptyView()
                    }
                },
                isActive: Binding(
                    get: { created != nil },
                    set: { active in if !active { created = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        )
        .sheet(item: $sheet) { item in
            switch item {
            case .picker:
                WorkspacePickerView(workspaces: store.workspaces) { workspace in
                    sheet = nil
                    create(workspace)
                }
            case .settings:
                SettingsView(server: server)
                    .environmentObject(servers)
            }
        }
    }

    private func create(_ workspace: Workspace) {
        store.createSession(workspace: workspace) { session in
            guard let session = session else { return }
            Haptics.success()
            self.created = session
        }
    }
}
