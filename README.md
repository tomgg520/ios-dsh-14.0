# DSH 移动端（iOS 14+）

把电脑上的 **DeepSeek Harness（DSH）** 装进 iPhone：在手机上继续电脑里的会话、发消息、看流式回复和工具调用、处理授权请求、切换模型。

- **iOS 客户端**：原生 SwiftUI，最低 **iOS 14.0**，无第三方依赖。
- **桥接服务**：一个零依赖的 Node 脚本，把 ACP 协议转成简单的 HTTP + SSE，跑在你的电脑上。
- 手机不直接跑模型，所有推理、文件操作都在电脑上完成。

> 说明：本工程是在 Windows 上写的，已用真实 DSH 对桥接服务做端到端测试、对 Swift 源码做语法校验、对 Xcode 工程做结构校验；但**没有 macOS/Xcode，无法替你编译真机包**。你需要一台 Mac 完成最后一步构建（见下文）。

---

## 架构

```
┌────────────────────┐        HTTP + SSE（局域网、配对码）        ┌──────────────────────┐
│  iPhone            │  ───────────────────────────────────▶   │  电脑                 │
│  DSHClient.app     │                                        │  bridge/server.mjs    │
│  SwiftUI / iOS 14  │  ◀───────────────────────────────────  │  （Node，无依赖）      │
└────────────────────┘        流式事件 / 工具调用 / 授权          └──────────┬───────────┘
                                                                           │ stdio · JSON-RPC（ACP v1）
                                                                           ▼
                                                                ┌──────────────────────┐
                                                                │ dsh --profile acp    │
                                                                │ DeepSeek Harness     │
                                                                └──────────────────────┘
```

桥接服务启动时自动找到本机的 DSH（Windows Desktop 版优先），以 `--profile acp` 启动一个 ACP 服务器，然后：

- 把 ACP 的 `session/update` 转成 SSE 事件（文本、思考、工具调用、用量、模型配置）。
- 把 ACP 的 `session/request_permission` 转成手机上的授权卡片。
- 提供会话列表 / 新建 / 续接 / 取消 / 切换模型等简单接口。

---

## 目录

```
dsh-ios/
├── DSHClient.xcodeproj/          # 可直接打开的 Xcode 工程（iOS 14.0，Swift 5）
├── DSHClient/
│   ├── App/                      # App 入口
│   ├── Models/                   # 数据模型
│   ├── Services/                 # HTTP、SSE、钥匙串、本地记录
│   ├── Stores/                   # 服务器 / 会话 / 聊天状态
│   ├── Support/                  # 主题、格式化
│   ├── Views/                    # 页面与组件
│   └── Resources/                # Info.plist、App 图标
├── .github/workflows/build-ipa.yml  # GitHub Actions 云构建未签名 IPA
├── scripts/build-ipa.sh             # 有 Mac 时一条命令构建 IPA
├── bridge/
│   ├── server.mjs                # 桥接服务（零依赖）
│   ├── start-bridge.cmd          # Windows 双击启动
│   ├── start-bridge.sh           # macOS / Linux 启动
│   └── config.example.json       # 配置示例
├── tools/
│   ├── gen-xcodeproj.mjs         # 生成并校验 Xcode 工程
│   └── make-icon.py              # 生成 App 图标（Pillow）
└── tests/                        # 桥接服务测试（协议 + 真实 DSH）
```

---

## 快速开始

### 0. 你需要

| 项目 | 要求 |
|---|---|
| 电脑 | Windows / macOS / Linux，已安装 DeepSeek Harness（Desktop 版或 `dsh` CLI），并且能在里面正常对话 |
| 手机 | iPhone，iOS **14.0** 及以上 |
| 网络 | 手机和电脑在**同一个 Wi-Fi** |
| 构建 | 一台 Mac + Xcode 13 或更新版本（推荐 15/16） |

### 1. 在电脑上启动桥接服务

**Windows（Desktop 版）**

双击 `bridge\start-bridge.cmd`。窗口会显示：

```
──────────────────────────────────────────────
  DSH iOS 桥接服务已启动
──────────────────────────────────────────────
  配对地址   http://192.168.1.5:8787
  配对码     K7F2-9QXM
  工作目录   C:\Users\you, C:\Users\you\Desktop
──────────────────────────────────────────────
```

第一次运行时 Windows 可能弹出防火墙提示，请勾选**专用网络**并允许。

**macOS / Linux**

```sh
cd bridge
npm install -g @deepseek-ai/dsh   # 若还没装 CLI
node server.mjs
```

或者先安装 Node.js 20+，再运行 `node server.mjs`；如果你的 DSH 不在 PATH 里，在 `bridge/config.json` 的 `dsh.command` 填写完整启动命令。

> 桥接服务本身零依赖，不需要 `npm install`。只有用 Desktop 版时才通过它自带的 Node 运行。

### 2. 构建 iOS App

1. 用 Xcode 打开 `DSHClient.xcodeproj`。
2. 选中 `DSHClient` target → **Signing & Capabilities**：
   - 勾选 **Automatically manage signing**；
   - **Team** 选择你的 Apple ID（没有开发者账号也可以，免费个人团队即可）；
   - 如果 Bundle Identifier 冲突，把 `com.dsh.ios.client` 改成别的，例如 `com.yourname.dsh`。
3. 用数据线连接 iPhone，在 Xcode 顶部选择你的手机，点 **Run**。
4. 首次运行时如果提示“不受信任的开发者”，到 iPhone 的 **设置 → 通用 → VPN 与设备管理** 里信任你的开发者证书。

> 免费 Apple ID 签名的 App **7 天后过期**，重新在 Xcode 里 Run 一次即可续期。想长期使用可以买开发者账号，或用 AltStore / Sideloadly 自签。

### 3. 配对

打开 App，填入桥接窗口里的：

- **电脑地址**：`192.168.1.5:8787`（可省略 `http://`，默认端口 8787）；
- **配对码**：`K7F2-9QXM`（可以不打中间的横线）。

点“连接”。第一次连接 iOS 会询问是否允许访问**本地网络**，必须选“允许”。

### 构建 IPA（TrollStore / 自签安装）

如果你有 TrollStore（巨魔），可以直接安装**未签名**的 IPA，不需要开发者证书，也不会 7 天过期。

**有 Mac：一条命令**

```sh
cd dsh-ios
chmod +x scripts/build-ipa.sh
./scripts/build-ipa.sh
```

生成 `dsh-ios/DSHClient.ipa`。用 AirDrop 或“文件”传到 iPhone，点开 → 用 TrollStore 安装。

**没有 Mac：GitHub Actions 云构建**

1. 在 GitHub 新建仓库（public 不消耗额度；private 会消耗 macOS 分钟）。
2. 让**仓库根目录**就是本目录的内容：`README.md`、`DSHClient.xcodeproj`、`DSHClient/`、`.github/` 都在根目录，不要多套一层 `dsh-ios/`。
3. 上传或推送代码（网页拖拽也可以）。
4. 打开仓库的 **Actions → Build unsigned IPA → Run workflow**。
5. 等 3~5 分钟，进入运行记录，下载 **DSHClient-ipa** artifact，解压得到 `DSHClient.ipa`。
6. 传到 iPhone（iCloud Drive / 网盘 / 局域网），用 TrollStore 打开安装。

> IPA 未签名：只能给 TrollStore 或 Sideloadly / AltStore 这类工具使用，不能直接安装。
> 构建日志重点看 `** BUILD SUCCEEDED **`；失败时把 `xcodebuild` 的报错行发我。
> 想改应用名：改 `Info.plist` 的 `CFBundleDisplayName`；想改 Bundle ID：改 Xcode target 的 Bundle Identifier（CI 构建不需要签名，改成什么都行）。

---

## 使用

### 会话

- 首页是桥接服务创建的会话列表（绿点表示正在运行），点 **+** 新建会话，选择一个电脑上的工作目录。
- 工作目录来自 `bridge/config.json` 的 `workspaces`；没配置时默认列出主目录、桌面、文稿和桥接服务当前目录。
- 也可以在“手动输入路径”里填写任意绝对路径（例如 `D:\work\project`）。

### 聊天

- 输入框回车即发送；回复是流式增量。
- “思考过程”可展开查看；工具调用会显示成卡片，点开看输入/输出。
- 右上角模型菜单可以切换 **模型** 和 **推理强度**（来自 ACP 的会话配置）。
- 生成过程中点红色停止按钮可以取消本轮。

### 授权

当 DSH 想执行需要确认的工具调用时，输入框上方会出现授权卡片，可以直接允许 / 拒绝。若不想每次都确认，可以在 `bridge/config.json` 里设置 `"autoApprove": true`（桥接服务会自动选择“允许一次”）。

> 注意：`autoApprove` 会跳过人工确认，请只在你信任的任务和网络里打开。

### 聊天记录

ACP 接口**不回放历史消息**，所以聊天记录保存在这台 iPhone 上（`Application Support/DSHClient/Sessions`）。换手机或在别的设备上看不到旧记录；电脑端的会话本身不受影响。

---

## 桥接服务配置

第一次运行会生成 `bridge/config.json`：

```json
{
  "port": 8787,
  "host": "0.0.0.0",
  "token": "K7F2-9QXM",
  "autoApprove": false,
  "workspaces": [],
  "defaultCwd": "",
  "dsh": { "command": [], "env": {} }
}
```

| 字段 | 说明 |
|---|---|
| `port` | 监听端口，默认 8787；被占用时会自动往后找，并写回配置 |
| `host` | 监听地址，`0.0.0.0` 表示局域网可访问；只想本机访问可改成 `127.0.0.1` |
| `token` | 配对码；删除或留空会重新生成 |
| `autoApprove` | 是否自动允许工具授权 |
| `workspaces` | 手机里可选的工作目录；可写字符串数组，或 `{ "name": "...", "path": "..." }` |
| `defaultCwd` | 新建会话的默认目录 |
| `dsh.command` | 覆盖 DSH 启动命令（字符串数组），例如 `["/usr/local/bin/dsh", "--profile", "acp"]` |
| `dsh.env` | 追加给 DSH 进程的环境变量，例如 `{ "DEEPSEEK_API_KEY": "sk-..." }` |

自动查找 DSH 的顺序：

1. `dsh.command`（如果配置了）；
2. Windows：`%LOCALAPPDATA%\Programs\DeepSeek Harness\DeepSeek Harness.exe` + 内置 `@deepseek-ai/dsh`；
3. macOS：`/Applications/DeepSeek Harness.app`；
4. PATH 上的 `dsh --profile acp`。

> Windows Desktop 版的凭据与 CLI 共用 `~/.dsh`，所以桥接服务可以直接用你桌面端已登录的 DeepSeek 账号。

---

## 常见问题

**连不上电脑**

- 确认手机和电脑在同一 Wi-Fi（不是访客网络 / AP 隔离）。
- 在电脑浏览器打开 `http://<地址>:8787`，应看到 `{"ok":true,...}`；打不开就是防火墙/端口问题。
- Windows：防火墙里允许 `DeepSeek Harness`（或 Node）的专用网络访问。
- 用 `ipconfig` 确认电脑的局域网 IPv4 地址，不要填 `127.0.0.1`。

**提示“配对码不正确”**

配对码在 `bridge/config.json` 的 `token` 字段，也在启动窗口里。重启桥接服务不会变；删掉配置文件会重新生成。

**提示“电脑端 DSH 未就绪”**

看桥接窗口的日志：通常是找不到 DSH，或 DSH 启动失败。可以在“设置 → 连接状态”看状态，或重新运行 `start-bridge.cmd`。

**发消息报 “no API key for provider route …”**

模型路由没有凭据。点右上角模型菜单，选择 **DeepSeek Account** 下的模型（桌面端已登录时可用），或在 `dsh.env` 里设置 `DEEPSEEK_API_KEY`。桥接默认使用 ACP profile 的 `deepseek-official` 路由，它需要显式 API key。

**提示没有本地网络权限**

到 iPhone **设置 → 隐私与安全性 → 本地网络**，打开 DSH 的开关；或删掉 App 重装后重新允许。

**免费签名 7 天后打不开**

重新用 Xcode Run 一次；或用 AltStore / Sideloadly 续签。TrollStore 安装的版本不受 7 天限制。

**TrollStore 安装 IPA 失败**

确认 IPA 是设备（arm64）构建而不是模拟器构建——本工程的脚本和 workflow 都使用 `-sdk iphoneos`。未签名 IPA 不能通过“设置 → 描述文件”安装，必须在 TrollStore 里打开，或先在“文件”里点开再共享给 TrollStore。也请确认 TrollStore 版本支持你的 iOS 版本。

**聊天记录丢了**

记录只存在手机上；删 App、清除记录或换设备都会丢。电脑端会话仍然保留，重新打开新会话即可继续对话。

---

## 安全说明

- 桥接服务用**配对码**做认证，HTTP + SSE 走**局域网明文**。只在你信任的网络里使用；不要把 8787 端口映射到公网。
- 拿到配对码的人可以在你的电脑上驱动 DSH（包括执行命令），请像对待密码一样对待它。
- `autoApprove: true` 会让工具调用不再询问，风险更高。
- App 的 `Info.plist` 为方便局域网 HTTP 连接开启了 `NSAllowsArbitraryLoads`；如果要上架 App Store，应改成仅允许本地网络，并使用 HTTPS。

---

## 开发

### 重新生成 Xcode 工程

新增/删除 Swift 文件后：

```sh
node tools/gen-xcodeproj.mjs
```

脚本会重新扫描 `DSHClient/`、生成 `project.pbxproj`，并用 OpenStep plist 解析器校验引用完整性。

### 语法检查（可选，开发用）

```sh
cd tools/swiftcheck
pnpm install          # 安装 tree-sitter + Swift 语法
node check.mjs        # 解析 DSHClient 下所有 .swift
```

### 桥接服务测试

`tests/` 里有两套测试：

```sh
# 1) 协议测试：用脚本化的假 ACP 代理验证授权往返、取消、鉴权、resume 配置
node tests/bridge-protocol.test.mjs

# 2) 真实测试：启动真实 dsh --profile acp，验证流式回复、工具调用、会话列表
node tests/bridge-e2e.test.mjs
```

Windows 上没有全局 Node 时，可以用 Desktop 自带的运行时：

```bat
set ELECTRON_RUN_AS_NODE=1
"%LOCALAPPDATA%\Programs\DeepSeek Harness\DeepSeek Harness.exe" tests\bridge-e2e.test.mjs
```

---

## HTTP 接口（桥接协议）

所有请求带 `Authorization: Bearer <token>`（SSE 也支持 `?token=`）。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/v1/health` | 健康检查、DSH 状态 |
| GET | `/v1/server` | 电脑名、平台、工作目录、DSH 状态、是否自动授权 |
| GET | `/v1/workspaces` | 可选工作目录 |
| GET | `/v1/sessions` | 会话列表（合并 ACP 会话与桥接元数据） |
| POST | `/v1/sessions` | 新建会话 `{cwd, title?}` |
| POST | `/v1/sessions/:id/resume` | 续接会话，返回 `{config}` |
| POST | `/v1/sessions/:id/prompt` | 发送消息 `{text}`，立即返回 `{turnId}` |
| POST | `/v1/sessions/:id/cancel` | 取消当前轮 |
| POST | `/v1/sessions/:id/config` | 修改模型/推理强度 `{configId, value}` |
| POST | `/v1/sessions/:id/close` | 关闭会话 |
| POST | `/v1/permissions/:id` | 回答授权 `{optionId}`，`{}` 表示取消 |
| GET | `/v1/events` | SSE 事件流（支持 `Last-Event-ID` 重放最近 800 条） |

SSE 事件类型：`hello`、`state`、`text`、`thought`、`tool`、`usage`、`config`、`title`、`turn_started`、`turn_ended`、`permission`、`permission_resolved`、`session_created`、`info`。

---

## 已知限制

- **不回放历史**：ACP 的 `session/list`、`session/resume` 不返回历史消息，历史只在本机。删除 App 会丢记录。
- **一次一轮**：同一会话同时只能有一轮在生成；需要并发请新建会话。
- **计划 / 命令面板 / 终端**：ACP 自动化接口不暴露 DSH 桌面端的这些展示能力，手机端只显示文本、思考、工具调用、用量和模型配置。
- **图片输入**：当前 ACP 配置不支持（`promptCapabilities.image = false`）。
- **明文 HTTP**：局域网内使用；公网部署需要自行加 TLS 反向代理。
- **本工程未在真机编译验证**：当前环境没有 macOS/Xcode。Swift 语法、pbxproj 结构、桥接协议均已校验，并提供了 GitHub Actions 云构建；如果构建报错，把日志发我即可。

---

## 许可

客户端与桥接服务代码可自由修改使用。DeepSeek Harness 本身遵循其各自许可。
