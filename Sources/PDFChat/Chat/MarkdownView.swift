import SwiftUI
import AppKit
import WebKit

/// 用 WKWebView 渲染 Markdown + LaTeX + 代码高亮。
/// JS 库（marked / KaTeX / highlight.js）通过 CDN 加载，本地无需打包资源。
struct MarkdownView: View {
    let text: String

    @State private var height: CGFloat = 1

    var body: some View {
        MarkdownWebView(text: text, height: $height)
            .frame(height: max(height, 1))
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = config.userContentController
        userContent.add(context.coordinator, name: "ready")
        userContent.add(context.coordinator, name: "height")

        let webView = PassthroughScrollWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // 公开 API：让 webview 背景透明，融入气泡底色。
        webView.underPageBackgroundColor = .clear
        // 禁用 webview 自身的捏合缩放，避免与 PDF 缩放手势冲突。
        webView.allowsMagnification = false
        context.coordinator.webView = webView

        webView.loadHTMLString(Self.htmlTemplate, baseURL: URL(string: "https://cdn.jsdelivr.net/")!)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.heightBinding = { value in
            DispatchQueue.main.async { self.height = value }
        }
        // 仅当文本变化时才重渲染，避免 height→frame→updateNSView 的循环
        if context.coordinator.lastText != text {
            context.coordinator.lastText = text
            context.coordinator.requestRender(text: text, in: nsView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - HTML 模板

    static let htmlTemplate: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="color-scheme" content="light dark">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.8.0/build/styles/github.min.css" media="(prefers-color-scheme: light)">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.8.0/build/styles/github-dark.min.css" media="(prefers-color-scheme: dark)">
    <style>
      html, body {
        margin: 0; padding: 0;
        background: transparent;
        overflow: hidden;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", Arial, sans-serif;
        font-size: 13px;
        line-height: 1.55;
        -webkit-font-smoothing: antialiased;
        text-rendering: optimizeLegibility;
        word-wrap: break-word;
        overflow-wrap: break-word;
      }
      @media (prefers-color-scheme: light) { body { color: #1d1d1f; } }
      @media (prefers-color-scheme: dark)  { body { color: #e6e6e6; } }
      p { margin: 0 0 8px; }
      p:last-child { margin-bottom: 0; }
      h1,h2,h3,h4,h5,h6 { margin: 12px 0 6px; line-height: 1.3; font-weight: 600; }
      h1 { font-size: 1.4em; } h2 { font-size: 1.25em; } h3 { font-size: 1.1em; }
      ul, ol { margin: 0 0 8px; padding-left: 22px; }
      li { margin: 2px 0; }
      blockquote {
        margin: 0 0 8px; padding: 2px 10px;
        border-left: 3px solid rgba(128,128,128,0.4);
        color: inherit; opacity: 0.85;
      }
      code {
        font-family: "SF Mono", Menlo, Consolas, monospace;
        font-size: 0.88em;
        padding: 1px 4px;
        border-radius: 4px;
        background: rgba(128,128,128,0.18);
      }
      pre {
        margin: 0 0 8px; padding: 8px 10px;
        border-radius: 6px;
        overflow-x: auto;
        background: rgba(128,128,128,0.12);
      }
      pre code { padding: 0; background: transparent; font-size: 0.85em; }
      a { color: #007aff; text-decoration: none; }
      a:hover { text-decoration: underline; }
      table {
        border-collapse: collapse; margin: 0 0 8px; display: block;
        overflow-x: auto; max-width: 100%;
      }
      th, td { border: 1px solid rgba(128,128,128,0.35); padding: 4px 8px; text-align: left; }
      th { background: rgba(128,128,128,0.15); font-weight: 600; }
      img { max-width: 100%; border-radius: 4px; }
      hr { border: none; border-top: 1px solid rgba(128,128,128,0.3); margin: 10px 0; }
      .katex-display { margin: 8px 0; overflow-x: auto; overflow-y: hidden; }
    </style>
    </head>
    <body></body>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
    <script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.8.0/build/highlight.min.js"></script>
    <script>
      marked.setOptions({ gfm: true, breaks: true });

      function postHeight() {
        var h = document.body.scrollHeight;
        try { window.webkit.messageHandlers.height.postMessage(String(h)); } catch (e) {}
      }

      function renderMarkdown(md) {
        try {
          var html = (window.marked ? marked.parse(md) : escapeHtml(md));
          document.body.innerHTML = html;
          if (window.hljs) {
            document.querySelectorAll('pre code').forEach(function (b) {
              try { hljs.highlightElement(b); } catch (e) {}
            });
          }
          if (window.renderMathInElement) {
            try {
              renderMathInElement(document.body, {
                delimiters: [
                  { left: '$$', right: '$$', display: true },
                  { left: '\\\\[', right: '\\\\]', display: true },
                  { left: '\\\\(', right: '\\\\)', display: false },
                  { left: '$', right: '$', display: false }
                ],
                throwOnError: false,
                ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code']
              });
            } catch (e) {}
          }
        } catch (e) {
          document.body.innerText = md;
        }
        postHeight();
      }

      function escapeHtml(s) {
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      }

      // 字体加载等导致的回流后重新测量高度
      if (window.ResizeObserver) {
        new ResizeObserver(function () { postHeight(); }).observe(document.body);
      }

      window.addEventListener('load', function () {
        try { window.webkit.messageHandlers.ready.postMessage('ready'); } catch (e) {}
      });
    </script>
    </html>
    """
}

// MARK: - Coordinator

extension MarkdownWebView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var heightBinding: ((CGFloat) -> Void)?
        var pageReady: Bool = false
        var queuedText: String?

        var lastText: String?
        private var lastRender: Date = .distantPast
        private var pending: DispatchWorkItem?

        func requestRender(text: String, in webView: WKWebView) {
            self.webView = webView
            if !pageReady {
                queuedText = text
                return
            }
            let now = Date()
            if now.timeIntervalSince(lastRender) >= 0.15 {
                renderNow(text: text)
            } else {
                pending?.cancel()
                let item = DispatchWorkItem { [weak self] in self?.renderNow(text: text) }
                pending = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
            }
        }

        private func renderNow(text: String) {
            guard let webView else { return }
            lastRender = Date()
            // .fragmentsAllowed：允许裸 String 作为顶层 JSON 值，避免
            // NSJSONSerialization 抛 ObjC 异常（Swift 的 try? 无法捕获 ObjC 异常会导致闪退）。
            guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("renderMarkdown(\(json))")
        }

        // MARK: WKScriptMessageHandler
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "ready":
                pageReady = true
                if let t = queuedText {
                    queuedText = nil
                    renderNow(text: t)
                }
            case "height":
                if let s = message.body as? String, let d = Double(s) {
                    heightBinding?(CGFloat(d))
                } else if let n = message.body as? NSNumber {
                    heightBinding?(CGFloat(n.doubleValue))
                }
            default: break
            }
        }
    }
}

/// WKWebView 子类：把滚轮事件转交给上层 ScrollView。
/// webview 高度已精确等于内容高度，内部无需滚动，转发是安全的，
/// 避免 WKWebView 内置 scroll view 吞掉 sidebar 的滚动。
final class PassthroughScrollWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
