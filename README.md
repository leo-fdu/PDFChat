# PDFChat

A PDF reader designed for macOS, featuring a built-in LLM sidebar. Connect any OpenAI-compatible API endpoint and ask questions while reading.

## Features

* **Set as the system default PDF opener**: Double-click any PDF to open it directly in PDFChat and start asking questions.

* **LLM sidebar**: Supports OpenAI-compatible endpoints (`baseURL` + `apiKey` + `model`), SSE streaming output, and stopping generation at any time.

* **Automatic context injection**

  * Uses the entire PDF as context by default.
  * After selecting a text passage, it automatically switches to “selection” context. The top status bar shows the context source and estimated token count, with one-click reset back to full-document context.

* **Multimodal image input**: The input box supports pasting images from the clipboard (`⌘V`) and selecting image files. Image understanding works as long as the connected model supports vision.

* **Preset prompts / Slash Commands**: Type `/` at the beginning of a line to open an autocomplete dropdown. Built-in commands include summarize, translate, explain, extract, and rewrite. You can add, delete, or edit commands in the settings page.

* **Keyboard shortcuts**

  | Shortcut    | Function         |
  | ----------- | ---------------- |
  | Enter       | Send message     |
  | Shift+Enter | New line         |
  | ⌘N          | New conversation |
  | ⌘O          | Open PDF         |
  | ⌘,          | Settings         |

* **Token and cost statistics**: Parses the `usage` field from each response. Prompt tokens, completion tokens, and cost are displayed below each message bubble. The bottom of the sidebar shows the real-time accumulated total for the current session.

* **Context limit warning**: When approaching the model’s context limit, the input box border turns orange.

* **Secure API key storage**: API keys are stored in macOS Keychain and are never written to disk in plaintext.

## System Requirements

* macOS 14.0 Sonoma or later
* Apple Silicon verified; Intel Macs need to build from source manually

## Quick Start

### Option 1: Use the Prebuilt Version

1. Drag `PDFChat.app` into `/Applications`.
2. On first launch, if macOS shows “cannot verify the developer,” right-click the app icon → Open → Open. This only needs to be done once.
3. After opening the app, press `⌘,` to enter Settings:

   * Choose a provider preset. OpenAI, DeepSeek, Moonshot, Zhipu, and SiliconFlow are supported for automatic `baseURL` filling, or you can enter it manually.
   * Enter the corresponding API key. It will be stored in Keychain.
   * Confirm the model list and the currently selected model.
   * Optional: In the “Pricing” tab, enter the input/output price for each model in dollars per 1M tokens. This is used for cost statistics.
4. Set PDFChat as the default PDF opener: in Finder, select any PDF → Get Info → Open with → choose PDFChat → Change All.

### Option 2: Build from Source

```sh
git clone https://github.com/leo-fdu/PDFChat.git
cd PDFChat
./build_app.sh        # Outputs PDFChat.app
open PDFChat.app
```

Xcode Command Line Tools and Swift 5.9+ are required.

## Usage Tips

* After selecting text in a PDF, the top of the sidebar will automatically show the “Selection” label. Questions will then be answered only based on that selected passage. Click the reset button to switch back to full-document context.
* When pasting an API key, make sure to remove leading and trailing spaces; otherwise, you may get a 401 error.
* After switching provider presets, re-enter the corresponding API key.
* Token statistics are accumulated only for the current session. Starting a new conversation with `⌘N` will reset the count.

## Project Structure

```text
PDFChat/
├── Sources/PDFChat/
│   ├── PDFChatApp.swift        # Entry point + onOpenURL + shortcuts
│   ├── ContentView.swift       # Main window
│   ├── PDF/                    # PDFKit rendering + context management
│   ├── Chat/                   # Sidebar, messages, input box, ViewModel
│   ├── API/                    # Configuration, Keychain, OpenAI-compatible client
│   ├── Settings/               # Settings, preset prompts, pricing
│   └── Utils/                  # Token estimation, image encoding
├── Package.swift
├── Info.plist
└── build_app.sh
```

## Privacy

* API keys are stored in macOS Keychain and are not written to files in plaintext.
* Other configuration data, including `baseURL`, model, pricing, and preset prompts, is stored at `~/Library/Preferences/com.niqi.pdfchat.plist`.
* Conversation history is not persisted and is discarded when the app is closed.
* No telemetry is collected, and no data is uploaded to third parties. Only the API endpoint you configure will receive your questions and PDF context.

## License

[MIT](LICENSE)
