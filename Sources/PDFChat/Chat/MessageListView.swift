import SwiftUI
import AppKit

struct MessageListView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.messages.isEmpty {
                        hintView
                    }
                    ForEach(viewModel.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                if let last = viewModel.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var hintView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("就 PDF 内容提问吧")
                .font(.headline)
            Text("选中文本自动作为上下文；输入 / 触发预置提示词")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 0) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // 图片
                if !message.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(message.images.enumerated()), id: \.offset) { _, img in
                            if let data = img.thumbData, let ns = NSImage(data: data) {
                                Image(nsImage: ns)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 120)
                                    .cornerRadius(6)
                            } else {
                                Image(systemName: "photo").frame(width: 80, height: 80)
                            }
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isUser ? Color.accentColor.opacity(0.18) : Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .frame(maxWidth: 320, alignment: isUser ? .trailing : .leading)
                }
                if let usage = message.usage {
                    metaLabel(usage: usage, cost: message.costUSD)
                } else if message.streaming && !message.text.isEmpty {
                    Text("生成中…").font(.caption2).foregroundColor(.secondary)
                }
            }
            if !isUser { Spacer(minLength: 0) }
        }
    }

    private func metaLabel(usage: ChatUsage, cost: Double?) -> some View {
        var s = "↑\(usage.promptTokens.formatted)  ↘\(usage.completionTokens.formatted)"
        if let c = cost { s += String(format: "  $%.4f", c) }
        return Text(s).font(.caption2).foregroundColor(.secondary)
    }
}