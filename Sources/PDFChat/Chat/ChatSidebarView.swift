import SwiftUI

struct ChatSidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var contextStore: PDFContextStore
    @ObservedObject var slashStore: SlashCommandStore = .shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：模型切换 + 新对话
            HStack(spacing: 8) {
                Menu(viewModel.currentModel) {
                    ForEach(settings.config.models, id: \.self) { m in
                        Button(m) { viewModel.switchModel(m) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button {
                    viewModel.newConversation()
                } label: {
                    Label("新对话", systemImage: "plus.bubble")
                }
                .help("新对话 (⌘N)")
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // context 状态条
            HStack(spacing: 6) {
                Image(systemName: contextStore.hasSelection ? "scissors" : "doc.text")
                    .foregroundColor(contextStore.hasSelection ? .orange : .accentColor)
                Text(contextStore.contextLabel)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("≈ \(contextStore.contextTokenCount.formatted) tok")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if contextStore.hasSelection {
                    Button {
                        contextStore.resetToFull()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("重置为全文")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))

            // 消息列表
            MessageListView(viewModel: viewModel)

            Divider()

            // 输入区
            ChatInputView(viewModel: viewModel, slashStore: slashStore, contextStore: contextStore)
                .padding(10)

            // 底部 token 统计条
            sessionStats
        }
        .frame(minWidth: 320, idealWidth: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var sessionStats: some View {
        HStack(spacing: 10) {
            Text("本次会话")
                .font(.caption2)
                .foregroundColor(.secondary)
            Label("\(viewModel.sessionTotalTokens.formatted) tok", systemImage: "bolt")
                .font(.caption2)
            Label(String(format: "$%.4f", viewModel.sessionCost), systemImage: "dollarsign.circle")
                .font(.caption2)
            Spacer()
            if let err = viewModel.error {
                Text(err).font(.caption2).foregroundColor(.red).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
    }
}