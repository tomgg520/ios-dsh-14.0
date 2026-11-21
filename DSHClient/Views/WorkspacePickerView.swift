import SwiftUI
import UIKit

struct WorkspacePickerView: View {
    let workspaces: [Workspace]
    let onSelect: (Workspace) -> Void

    @Environment(\.presentationMode) private var presentation
    @State private var manualPath = ""
    @State private var showManual = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("电脑上的工作目录")) {
                    ForEach(workspaces) { workspace in
                        Button(action: { choose(workspace) }) {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workspace.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(workspace.path)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    Button(action: { showManual.toggle() }) {
                        Label("手动输入路径", systemImage: "keyboard")
                            .font(.system(size: 14))
                    }
                }

                if showManual {
                    Section(header: Text("绝对路径"), footer: Text("路径必须存在于电脑上，例如 D:\\work\\project。")) {
                        TextField("D:\\work\\project", text: $manualPath)
                            .font(.system(size: 13, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button("使用此路径") {
                            let path = manualPath.trimmed
                            guard !path.isEmpty else { return }
                            choose(Workspace(name: folderName(path), path: path))
                        }
                        .disabled(manualPath.trimmed.isEmpty)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }

    private func choose(_ workspace: Workspace) {
        onSelect(workspace)
        presentation.wrappedValue.dismiss()
    }

    private func folderName(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") || path.hasSuffix("\\") ? String(path.dropLast()) : path
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? trimmed : name
    }
}
