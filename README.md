# PDFChat

A macOS PDF reader with a built-in LLM sidebar — point it at any OpenAI-compatible endpoint and chat while you read.

## Features

- **Set as the system default PDF app**: double-click any PDF to open it in PDFChat and start asking
- **LLM sidebar**: OpenAI-compatible endpoint (baseURL + apiKey + model); SSE streaming; stop generation at any time
- **Automatic context injection**
  - By default, the entire PDF is used as context
  - Select text and it switches to "selection" context; the status bar shows the source with a token estimate, one click to reset back to full document
- **Multimodal image input**: paste from clipboard (⌘V) or pick a file; works with any model that supports vision
- **Preset prompts (slash commands)**: type `/` at the start of a line for autocomplete; ships with 总结 / 翻译 / 解释 / 提取 / 改写; add, edit and delete in Settings
- **Keyboard shortcuts**

  | Shortcut | Action |
  |---|---|
  | Enter | Send message |
  | Shift+Enter | New line |
  | ⌘N | New conversation |
  | ⌘O | Open PDF |
  | ⌘, | Settings |

- **Token & cost tracking**: parses `usage` from each response; prompt/completion tokens and cost are shown under each bubble; the sidebar footer accumulates per-session totals in real time
- **Over-limit warning**: the input box border turns orange as you approach the model's context limit
- **Secure API key storage**: stored in the macOS Keychain, never written to disk in plain text

## System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (verified); Intel Macs need to build from source

## Quick Start

### Option 1: Use the prebuilt app

1. Drag `PDFChat.app` into `/Applications`
2. On first launch, if macOS warns the developer "cannot be verified": right-click the icon → Open → Open (a one-time allow)
3. Open Settings with ☄⌘,:
   - Pick a provider preset (OpenAI / DeepSeek / Moonshot / Zhipu / SiliconFlow) to auto-fill the baseURL, or enter it manually
   - Enter the matching API key (stored in Keychain)
   - Confirm the model list and the active model
   - (Optional) On the "Pricing" tab, set per-model input/output prices ($/1M tokens) for cost tracking
4. Set PDFChat as the default PDF app: in Finder, select any PDF → Get Info → Open With → PDFChat → "Change All…"
5. (Optional) Add a "New Window" menu item via ⌘⇧N to keep multiple PDFs side by side — each window has its own conversation

### Option 2: Build from source

```sh
git clone https://github.com/leo-fdu/PDFChat.git
cd PDFChat
./build_app.sh        # produces PDFChat.app
open PDFChat.app
```

Requires Xcode Command Line Tools and Swift 5.9+.

## Usage Tips

- After selecting text in a PDF, the sidebar shows a "selection" tag; questions then target just that passage; hit the reset button to switch back to the full document
- Trim leading/trailing whitespace when pasting an API key, otherwise you may get a 401
- After switching provider presets, re-enter the corresponding API key
- Token stats accumulate for the current session only; a new conversation (⌘N) resets them

## Project Structure

```
PDFChat/
├── Sources/PDFChat/
│   ├── PDFChatApp.swift        # Entry point + onOpenURL + keyboard shortcuts
│   ├── ContentView.swift       # Main window
│   ├── PDF/                    # PDFKit rendering + context management
│   ├── Chat/                   # Sidebar, messages, input box, view model
│   ├── API/                    # Config, Keychain, OpenAI-compatible client
│   ├── Settings/               # Settings, preset prompts, pricing
│   └── Utils/                  # Token estimation, image encoding
├── Package.swift
├── Info.plist
└── build_app.sh
```

## Privacy

- The API key is stored in the macOS Keychain, never written to a file in plain text
- Other config (baseURL, models, pricing, preset prompts) is stored in `~/Library/Preferences/com.niqi.pdfchat.plist`
- Conversation history is not persisted and is discarded on close
- No telemetry is collected and nothing is uploaded to third parties (only your configured API endpoint receives your questions and the PDF context)

## License

[MIT](LICENSE)