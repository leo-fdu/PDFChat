# PDFChat

一个为 macOS 设计的 PDF 阅读器，内置 LLM 侧边栏，接入任意 OpenAI 兼容接口即可边读边问。

## 功能特性

- **设为系统默认 PDF 打开方式**：双击任意 PDF 直接在 PDFChat 中打开并提问
- **LLM 侧边栏**：OpenAI 兼容端点（baseURL + apiKey + model），SSE 流式输出，可随时停止生成
- **上下文自动注入**
  - 默认把整篇 PDF 作为上下文
  - 选中一段文字后自动切换为「选区」上下文，顶部状态条显示来源与 token 估算，一键重置回全文
- **多模态图片输入**：输入框支持剪贴板粘贴（⌘V）、文件选择；只要接入的模型支持 vision 即可看图
- **预制提示词（Slash Commands）**：行首输入 `/` 弹出补全下拉，内置 总结/翻译/解释/提取/改写，可在设置页增删改
- **快捷键**

  | 快捷键 | 功能 |
  |---|---|
  | Enter | 发送消息 |
  | Shift+Enter | 换行 |
  | ⌘N | 新对话 |
  | ⌘O | 打开 PDF |
  | ⌘, | 设置 |

- **Token 与费用统计**：解析每次响应的 `usage`，消息气泡下显示 prompt/completion tokens 与费用；侧边栏底部实时累加当前会话总量
- **超限预警**：接近模型上下文上限时输入框边框变橙
- **API Key 安全存储**：写入 macOS Keychain，不明文落盘

## 系统要求

- macOS 14.0（Sonoma）或更高
- Apple Silicon（已验证）；Intel Mac 需自行从源码编译

## 快速开始

### 方式一：直接使用预编译版

1. 将 `PDFChat.app` 拖入 `/Applications`
2. 首次双击若提示「无法验证开发者」：右键点击图标 → 打开 → 打开（一次性放行即可）
3. 打开后按 ⌘, 进入设置：
   - 选择服务商预设（OpenAI / DeepSeek / Moonshot / 智谱 / SiliconFlow）自动填充 baseURL，或手动填写
   - 填入对应 API Key（存入 Keychain）
   - 确认模型列表与当前模型
   - （可选）在「价格」标签页为每个模型填输入/输出单价（$/1M tokens），用于费用统计
4. 设为默认 PDF 打开方式：在 Finder 选中任意 PDF → 显示简介 → 打开方式 → 选 PDFChat → 「全部更改」

### 方式二：从源码构建

```sh
git clone https://github.com/leo-fdu/PDFChat.git
cd PDFChat
./build_app.sh        # 产出 PDFChat.app
open PDFChat.app
```

需要 Xcode Command Line Tools 与 Swift 5.9+。

## 使用提示

- 选中 PDF 中的文字后，侧边栏顶部会自动显示「选区」标签，此时提问只针对该段；点重置按钮回到全文
- 粘贴 API Key 时注意去除首尾空白，否则可能 401
- 切换服务商预设后请重新填写对应的 API Key
- Token 统计仅当前会话累计，新对话（⌘N）会清零

## 项目结构

```
PDFChat/
├── Sources/PDFChat/
│   ├── PDFChatApp.swift        # 入口 + onOpenURL + 快捷键
│   ├── ContentView.swift      # 主窗口
│   ├── PDF/                    # PDFKit 渲染 + 上下文管理
│   ├── Chat/                   # 侧边栏、消息、输入框、View Model
│   ├── API/                    # 配置、Keychain、OpenAI 兼容客户端
│   ├── Settings/               # 设置、预制提示词、价格
│   └── Utils/                  # Token 估算、图片编码
├── Package.swift
├── Info.plist
└── build_app.sh
```

## 隐私

- API Key 存于 macOS Keychain，不明写文件
- 其余配置（baseURL、模型、价格、预制提示词）存于 `~/Library/Preferences/com.niqi.pdfchat.plist`
- 对话历史不持久化，关闭即丢失
- 不收集任何遥测，不上传任何数据到第三方（仅你配置的 API 端点会收到你的提问与 PDF 上下文）

## 许可证

[MIT](LICENSE)