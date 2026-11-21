import SwiftUI

struct ChatView: View {
    @StateObject private var store: ChatStore
    @State private var draft = ""
    @State private var showInfo = false

    @Environment(\.colorScheme) private var scheme

    init(session: SessionSummary, server: ServerProfile) {
        _store = StateObject(wrappedValue: ChatStore(session: session, server: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner

            messageList

            if let request = store.permission {
                PermissionCard(request: request) { optionId in
                    store.answer(permission: request, optionId: optionId)
                }
                .transition(.opacity)
            }

            Composer(
                text: $draft,
                isStreaming: store.isStreaming,
                isCancelling: store.isCancelling,
                onSend: sendDraft,
                onStop: { store.cancel() }
            )
        }
        .background(Theme.background(scheme).edgesIgnoringSafeArea(.all))
        .navigationBarTitle(store.title, displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    if !store.configOptions.isEmpty {
                        modelMenu
                    }
                    Button(action: { showInfo = true }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                    }
                }
            }
        }
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        .sheet(isPresented: $showInfo) {
            SessionInfoSheet(store: store)
        }
    }

    // MARK: - 顶部状态

    @ViewBuilder
    private var statusBanner: some View {
        if store.authFailed {
            ConnectionBanner(text: "配对码已失效，请到设置里重新配对", isError: true)
        } else if !store.connected {
            ConnectionBanner(text: store.statusDetail ?? "正在连接电脑…", isError: false)
        } else if store.dshState == "failed" || store.dshState == "unreachable" {
            ConnectionBanner(text: "电脑端 DSH 未就绪：\(store.statusDetail ?? store.dshState)", isError: true)
        } else if store.dshState == "starting" || store.dshState == "restarting" || store.dshState == "stopped" {
            ConnectionBanner(text: "正在启动电脑端 DSH…", isError: false)
        } else if let banner = store.banner {
            ConnectionBanner(text: banner, isError: true)
        }
    }

    // MARK: - 消息

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if store.messages.isEmpty {
                        emptyState
                    }

                    ForEach(store.messages) { message in
                        MessageRow(message: message)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .onChange(of: store.scrollTick) { _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.messages.count) { _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("开始一段新对话")
                    .font(.system(size: 22, weight: .bold))
                Text(store.session.cwd)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        draft = ""
                        store.send(suggestion)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.accent)
                            Text(suggestion)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Theme.surface(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.border(scheme), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 8)
    }

    private var suggestions: [String] {
        [
            "先看看这个目录里有什么，简单介绍一下项目结构",
            "帮我把这个项目跑起来，需要的话先安装依赖",
            "找出代码里最需要修复的三个问题",
        ]
    }

    // MARK: - 工具栏

    private var modelMenu: some View {
        Menu {
            ForEach(store.configOptions.filter { $0.type == "select" }) { option in
                ForEach(option.choices) { choice in
                    Button(action: {
                        store.select(configId: option.id, value: choice.value)
                    }) {
                        HStack {
                            Text(choiceLabel(option, choice))
                            if choice.value == option.currentValue.stringValue {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(modelLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .frame(maxWidth: 108)
        }
    }

    private func choiceLabel(_ option: ConfigOption, _ choice: ConfigChoice) -> String {
        switch option.id {
        case "model":
            return choice.name
        case "reasoning_effort":
            return "推理：\(choice.name)"
        default:
            return "\(option.name)：\(choice.name)"
        }
    }

    private var modelLabel: String {
        if let model = store.configOptions.first(where: { $0.id == "model" }) {
            return model.selectedName
        }
        return "模型"
    }

    private func sendDraft() {
        let text = draft
        guard !text.trimmed.isEmpty else { return }
        draft = ""
        store.send(text)
    }
}

// MARK: - 会话信息

struct SessionInfoSheet: View {
    @ObservedObject var store: ChatStore
    @Environment(\.presentationMode) private var presentation
    @State private var confirmClear = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("会话")) {
                    InfoRow(label: "工作目录", value: store.session.cwd, mono: true)
                    InfoRow(label: "上下文用量", value: store.usageText ?? "—")
                    InfoRow(label: "消息条数", value: "\(store.messages.count)")
                }

                Section {
                    Button(action: {
                        store.closeSession {
                            presentation.wrappedValue.dismiss()
                        }
                    }) {
                        Text("在电脑端关闭会话")
                    }

                    Button(action: { confirmClear = true }) {
                        Text("清空本机聊天记录")
                            .foregroundColor(Theme.danger)
                    }
                }

                Section(header: Text("说明")) {
                    Text("电脑端的 ACP 接口不会回放历史消息，所以聊天记录保存在这台 iPhone 上；在别的设备上看不到。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationBarTitle("会话信息", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { presentation.wrappedValue.dismiss() }
                }
            }
            .alert(isPresented: $confirmClear) {
                Alert(
                    title: Text("清空本机记录？"),
                    message: Text("此操作不可恢复，电脑端的会话不受影响。"),
                    primaryButton: .destructive(Text("清空")) { store.clearLocal() },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, design: mono ? .monospaced : .default))
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}
