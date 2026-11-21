import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject private var servers: ServerStore
    @Environment(\.colorScheme) private var scheme

    @State private var address = ""
    @State private var code = ""
    @State private var connecting = false
    @State private var error: String?

    private var canConnect: Bool {
        !address.trimmed.isEmpty && !code.trimmed.isEmpty && !connecting
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.bubbleGradient)
                            .frame(width: 72, height: 72)
                        Text("DSH")
                            .font(.system(size: 21, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .shadow(color: Theme.accent.opacity(0.35), radius: 16, x: 0, y: 8)

                    Text("DSH 移动端")
                        .font(.system(size: 24, weight: .bold))
                    Text("在你的 iPhone 上继续电脑里的\nDeepSeek Harness 会话")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .listRowBackground(Color.clear)
            }

            Section(header: Text("配对电脑")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("电脑地址")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("192.168.1.5:8787", text: $address)
                        .font(.system(size: 16, design: .monospaced))
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("配对码")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("ABCD-1234", text: $code)
                        .font(.system(size: 16, design: .monospaced))
                        .keyboardType(.asciiCapable)
                        .autocapitalization(.characters)
                        .disableAutocorrection(true)
                }
                .padding(.vertical, 2)

                if let error = error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.danger)
                        .lineSpacing(2)
                }
            }

            Section {
                Button(action: connect) {
                    HStack(spacing: 8) {
                        if connecting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(connecting ? "正在连接…" : "连接")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canConnect))
                .disabled(!canConnect)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(header: Text("怎么用")) {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "在电脑上双击运行 bridge/start-bridge.cmd（macOS / Linux 见 README）")
                    step(2, "命令窗口会显示一个地址和一个配对码")
                    step(3, "手机与电脑连同一个 Wi-Fi，把地址和配对码填到上面")
                }
                .padding(.vertical, 4)
            }

            if !servers.profiles.isEmpty {
                Section(header: Text("已配对")) {
                    ForEach(servers.profiles) { profile in
                        Button(action: { servers.activate(profile.id) }) {
                            HStack(spacing: 10) {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(profile.baseURL)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete(perform: deleteProfiles)
                }
            }

            Section {
                Text("第一次连接时 iOS 会询问“是否允许访问本地网络”，请选择“允许”。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .background(Theme.background(scheme).edgesIgnoringSafeArea(.all))
    }

    private func step(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connect() {
        error = nil
        guard let url = ServerAddress.normalize(address) else {
            error = "地址格式不正确，例如 192.168.1.5:8787"
            return
        }
        let token = ServerAddress.normalizeCode(code)
        guard token.count >= 6 else {
            error = "配对码格式不正确，终端里会显示类似 ABCD-1234 的码"
            return
        }

        hideKeyboard()
        connecting = true

        let api = APIClient(baseURL: url, token: token)
        api.get("/v1/server") { (result: Result<ServerInfoResponse, APIError>) in
            self.connecting = false
            switch result {
            case .success(let info):
                let host = url.host ?? "我的电脑"
                let name = info.name.isEmpty ? host : info.name
                self.servers.add(ServerProfile(name: name, baseURL: url.absoluteString, token: token))
            case .failure(let failure):
                self.error = failure.localizedDescription
            }
        }
    }

    private func deleteProfiles(_ offsets: IndexSet) {
        let ids = offsets.map { servers.profiles[$0].id }
        for id in ids {
            servers.remove(id)
        }
    }
}
