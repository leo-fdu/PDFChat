import SwiftUI

struct ChatSidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var contextStore: PDFContextStore
    @ObservedObject var historyStore: ConversationHistoryStore
    @ObservedObject var slashStore: SlashCommandStore = .shared
    @ObservedObject var settings = AppSettings.shared

    @AppStorage("chat.inputPaneHeight") private var inputPaneHeight: Double = 200
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：模型切换 + 推理强度 + 历史 + 新对话
            HStack(spacing: 8) {
                Menu(viewModel.currentModel) {
                    ForEach(settings.config.models, id: \.self) { m in
                        Button(m) { viewModel.switchModel(m) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                reasoningMenu

                Spacer()

                Button {
                    showHistory = true
                } label: {
                    Label("历史对话", systemImage: "clock.arrow.circlepath")
                }
                .help("查看此 PDF 的历史对话")
                .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                    HistoryListView(historyStore: historyStore, viewModel: viewModel)
                        .frame(width: 340, height: 400)
                }

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

            // 输入区：无边框，浅灰色背景；拖拽分隔条（隐形）调整高度
            InputResizeHandle(height: $inputPaneHeight)
            ChatInputView(viewModel: viewModel, slashStore: slashStore, contextStore: contextStore)
                .frame(height: inputPaneHeight)
                .background(Color.secondary.opacity(0.1))
                .padding(.bottom, 4)

            // 底部 token 统计条
            sessionStats
        }
        .frame(minWidth: 320, idealWidth: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 推理强度（reasoning_effort）快速切换

    private var currentEffort: ReasoningEffort {
        ReasoningEffort(string: settings.config.reasoningEffort)
    }

    private var reasoningMenu: some View {
        Menu {
            ForEach(ReasoningEffort.allCases) { effort in
                Button {
                    settings.config.reasoningEffort = effort == .unset ? nil : effort.rawValue
                    settings.save()
                } label: {
                    if effort == currentEffort {
                        Label(effort.label, systemImage: "checkmark")
                    } else {
                        Text(effort.label)
                    }
                }
            }
        } label: {
            Label("推理：\(currentEffort.label)", systemImage: "brain")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("调整推理强度（reasoning_effort），默认表示由服务端决定")
    }

    // MARK: - 历史对话（弹出面板）

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
            if viewModel.isStreaming {
                Button {
                    viewModel.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("中断当前生成")
            }
            if let err = viewModel.error {
                Text(err).font(.caption2).foregroundColor(.red).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
    }
}

/// 历史对话弹出面板：点击恢复该对话，右侧垃圾桶删除；
/// popover 为 transient 行为，点击面板外任意空白处自动收回。
private struct HistoryListView: View {
    @ObservedObject var historyStore: ConversationHistoryStore
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        Group {
            if historyStore.conversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("暂无历史对话")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(historyStore.conversations) { conv in
                            Button {
                                viewModel.restore(messages: historyStore.load(conv))
                            } label: {
                                HStack(spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conv.title)
                                            .font(.callout)
                                            .foregroundColor(conv.id == historyStore.currentConversationID ? .accentColor : .primary)
                                            .lineLimit(1)
                                        HStack(spacing: 4) {
                                            Text(conv.updatedAt, style: .date)
                                            Text(conv.updatedAt, style: .time)
                                            Text("· \(conv.messages.count) 条")
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                    Spacer(minLength: 4)
                                    if conv.id == historyStore.currentConversationID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                    Button {
                                        if conv.id == historyStore.currentConversationID {
                                            viewModel.newConversation()
                                        }
                                        historyStore.delete(conv)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("删除此对话")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(conv.id == historyStore.currentConversationID
                                            ? Color.accentColor.opacity(0.08) : Color.clear)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

/// 输入区分隔条：上下拖拽调整输入区高度，高度经 AppStorage 持久化。
/// 视觉上完全隐形（无 bar、无指示条），仅提供拖拽区域与调整光标。
/// 必须用 .global 坐标系：分隔条会随输入区变大而上移，若用默认局部坐标系，
/// 手势位移会被自身移动抵消一半（鼠标移 2px 高度只变 1px），不跟手。
private struct InputResizeHandle: View {
    @Binding var height: Double
    @State private var dragStartHeight: Double = 0
    @State private var dragStartMouseY: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 10)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            dragStartHeight = height
                            dragStartMouseY = value.startLocation.y
                            isDragging = true
                        }
                        // 全局坐标 y 向下为正：鼠标上移 → y 变小 → 高度增大，严格 1:1
                        let delta = dragStartMouseY - value.location.y
                        height = min(max(dragStartHeight + delta, 120), 700)
                    }
                    .onEnded { _ in isDragging = false }
            )
    }
}
