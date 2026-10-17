# PDFChat

A focused native macOS PDF reader with a configurable LLM sidebar. Read the PDF, quote a passage, ask a question, and follow page citations back to the document. PDFChat does not edit or write annotations into your PDF.

## Reading and chatting

- **Complete PDF by default.** The input card selects **PDF 文件** on opening a document. Each request includes the original PDF bytes as a file input, including visual content. Nothing is uploaded merely by opening a PDF: sending a question starts the request.
- **Explicit text alternative.** Click **PDFKit 文字** to extract and send the complete text with physical page markers. This is useful for text-heavy long documents and providers without PDF support. The app checks an estimated text/context budget and never silently truncates or silently switches modes. Scanned PDFs without extractable text produce an actionable message.
- **Quotes stay pinned.** Select text and choose 提问, 解释, or 翻译. The quoted text and physical page number appear above the composer and are saved with the question. Changing the selection or turning a page does not change the pinned quote. The quote accompanies the selected full-document input mode.
- **Read comfortably.** Search (`⌘F`, Enter to run), page navigation, document outline, fit width, zoom, and per-document page/zoom restoration. Drag the visible 12-point divider to resize the sidebar; it can also receive focus and use the left/right arrow keys.
- **Images.** Paste an image or use the `+` menu to pick an image or attach the current PDF page screenshot.
- **Conversation history.** Local automatic persistence, one history collection per PDF content hash. Moving or renaming an unchanged PDF preserves its history. Existing path-based histories migrate automatically. History includes quotes, model labels, input mode, tool progress, and reported usage.

## Connections

Open Settings (`⌘,`) and add a named connection. Each connection keeps its own base URL, model list, protocol, capability switches, pricing, and Keychain API key. Existing v1 configuration and its key are retained as the default connection.

Choose the protocol your endpoint actually implements:

| Protocol | PDF input | Tools | Web search |
|---|---|---|---|
| Chat Completions | `file` content with base64 PDF; provider/model must support it | Function calls executed by PDFChat | Brave Search key + web tools |
| Responses | `input_file` with base64 PDF; provider/model must support it | Function calls executed by PDFChat | Provider-hosted `web_search`; provider must support it |

An “OpenAI-compatible” URL does **not** guarantee PDF, vision, reasoning, or tool support. Provider errors are shown with their details and a retry button; switch explicitly to **PDFKit 文字** if file input is rejected. The app has a conservative 50 MB PDF guard; providers may impose lower limits. PDF page images also consume context and tokens. Full text mode cannot make a document larger than the model's context fit automatically.

Use **获取模型列表** to query `/models`, or enter a model ID manually. **测试连接** sends a small text request to the selected model (provider usage may be charged); it verifies basic connectivity, not every optional capability. Local endpoints can use an empty API key. Leave reasoning at 默认 unless the model supports the selected effort value. Turn off streamed usage if a compatible provider rejects `stream_options`.

## Reading tools

Document tools are enabled by default. Network access is opt-in using the sidebar's 阅读工具 menu or Settings → 工具.

- `search_pdf`: find text and physical page references in the current PDF.
- `read_pdf_page`: read a page's extracted text.
- `view_pdf_page`: send a rendered page image; disable for models without vision.
- `read_webpage`: fetch public HTTP(S) text pages without browser cookies or API credentials.
- `web_search`: Brave Search, when a separate Brave Search API key is configured.
- Responses connections can instead enable the provider's built-in `web_search`.

The app executes returned tool calls, sends their results back, and continues the answer. It supports fragmented/multiple function calls, cancellation, and a maximum of 12 rounds / 16 calls per round. External webpage text is capped at 24,000 characters and marked when truncated. Tools cannot run shell commands or modify PDFs. Enable function tools as well as networking to use webpage/Brave tools. Web search and other provider tool fees are not included in the displayed model-price estimate.

PDF citations use `[第 N 页](pdfchat://page/N)` and navigate to physical PDF page N. Citation wording/page accuracy still depends on the model; the reader provides navigation rather than claiming automatic factual verification.

## Rendering and responsiveness

The transcript uses one local WebView with incremental message updates, independent scrolling, and bundled Markdown/KaTeX resources. No CDN scripts are fetched at runtime. Completed messages are not re-rendered for each new token. Selecting answer text preserves the selection; scrolling upward pauses following until you return to the bottom or click 回到最新. Streaming is batched, pending text is flushed on stop, and superseded requests cannot update a newer conversation. Markdown HTML is sanitized and external image loading is disabled.

PDF text extraction, image rendering, hashing, and base64 preparation use a separate document reader. History encoding/writes run on a serial background queue; normal application quit drains pending writes. A forced process kill can still lose an unfinished response.

## Build and run

Requires macOS 14+, Swift 5.9+ and Apple command-line developer tools.

```sh
./build_app.sh
open PDFChat.app
```

The bundle includes all rendering assets. Quit an already-running older PDFChat instance before opening the newly built app. You can then copy `PDFChat.app` into `/Applications`.

To set it as the default reader: Finder → select a PDF → Get Info → Open With → PDFChat → Change All.

## Verification

Tests require full Xcode (Command Line Tools alone may not include XCTest):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The suite uses synthetic PDFs and a loopback mock API, never a user's API key. It covers file payloads, explicit text extraction, real page tools, fragmented SSE/function calls in both protocols, provider errors, incomplete streams, request cancellation isolation, legacy decoding, offline Markdown/math, HTML sanitization, scroll/selection preservation, and resize behavior. Native UI checks should additionally exercise divider dragging, PDF selection actions, search, and first-open sizing.

## Storage and privacy

API/search keys are stored in macOS Keychain. Connections/preferences use UserDefaults. Histories are JSON under `~/Library/Application Support/PDFChat/History/` and can contain quoted text and attached images. PDF requests go to the configured endpoint. When enabled, search queries go to the configured search provider and page reads contact their target websites. The PDF file itself is never rewritten. No telemetry is collected.

Bundled dependencies: marked 15.0.12, DOMPurify 3.2.6, KaTeX 0.16.22. Their licenses are included in `Sources/PDFChat/Resources/Web/`.

## License

[MIT](LICENSE)
