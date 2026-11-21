import SwiftUI
import UIKit

struct SettingsView: View {
    let server: ServerProfile

    @EnvironmentObject private var servers: ServerStore
    @Environment(\.presentationMode) private var presentation

    @State private var address: String
    @State private var code: String
    @State private var info: ServerInfoResponse?
    @State private var error: String?
    @State private var confirmClear = false

    init(server: ServerProfile) {
        self.server = server
        _address = State(initialValue: server.baseURL)
        _code = State(initialValue: server.token)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("服务器")) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("地址")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("192.168.1.5:8787", text: $address)
                            .font(.system(size: 15, design: .monospaced))
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("配对码")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("ABCD-1234", text: $code)
                            .font(.system(size: 15, design: .monospaced))
                            .keyboardType(.asciiCapable)
                            .autocapitalization(.characters)
                            .disableAutocorrection(true)
                    }
                    .padding(.vertical, 2)

                    if let error = error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.danger)
                    }

                    Button("保存并重新连接") { save() }
                }

                Section(header: Text("连接状态")) {
                    InfoRow(label: "电脑", value: info?.name ?? "—")
                    InfoRow(label: "桥接服务", value: info?.bridge ?? "—")
                    InfoRow(label: "DSH", value: info?.dsh.state ?? "—")
                    InfoRow(label: "自动授权", value: (info?.autoApprove ?? false) ? "开" : "关（在手机上确认）")
                }

                Section {
                    Button(action: {
                        servers.deactivate()
                        presentation.wrappedValue.dismiss()
                    }) {
                        Text("断开连接")
                            .foregroundColor(Theme.danger)
                    }
                }

                Section(footer: Text("只删除这台 iPhone 上的记录，电脑端会话不受影响。")) {
                    Button(action: { confirmClear = true }) {
                        Text("清除本机聊天记录")
                            .foregroundColor(Theme.danger)
                    }
                }

                Section(header: Text("关于")) {
                    InfoRow(label: "版本", value: "1.0 (1)")
                    InfoRow(label: "适配", value: "iOS 14.0 及以上")
                    Text("DSH 移动端通过 Agent Client Protocol 连接电脑上的 DeepSeek Harness；所有模型调用都在电脑上完成。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { presentation.wrappedValue.dismiss() }
                }
            }
            .onAppear(perform: loadInfo)
            .alert(isPresented: $confirmClear) {
                Alert(
                    title: Text("清除本机聊天记录？"),
                    message: Text("此操作不可恢复。"),
                    primaryButton: .destructive(Text("清除")) { TranscriptStore.shared.deleteAll() },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }

    private func loadInfo() {
        let api = APIClient(baseURL: server.url, token: server.token)
        api.get("/v1/server") { (result: Result<ServerInfoResponse, APIError>) in
            if case .success(let value) = result {
                self.info = value
            }
        }
    }

    private func save() {
        error = nil
        guard let url = ServerAddress.normalize(address) else {
            error = "地址格式不正确"
            return
        }
        let token = ServerAddress.normalizeCode(code)
        guard token.count >= 6 else {
            error = "配对码格式不正确"
            return
        }

        var updated = server
        updated.baseURL = url.absoluteString
        updated.token = token
        servers.update(updated)
        servers.activate(updated.id)
        presentation.wrappedValue.dismiss()
    }
}
