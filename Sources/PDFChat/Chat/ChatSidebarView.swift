import SwiftUI

struct ChatSidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var contextStore: PDFContextStore
    @ObservedObject var historyStore: ConversationHistoryStore
    @ObservedObject private var settings = AppSettings.shared
    @State private var showHistory = false
    @State private var showStats = false
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(.tint).font(.system(size: 19))
                VStack(alignment: .leading, spacing: 3) {
                    Text("阅读助手").font(.system(size: 14, weight: .semibold))
                    Menu {
                        ForEach(settings.profiles) { profile in
                            Button(profile.name) { settings.select(profile.id) }
                        }
                        Divider()
                        ForEach(settings.config.models, id: \.self) { model in
                            Button { viewModel.switchModel(model) } label: {
                                if model == settings.config.model { Label(model, systemImage: "checkmark") } else { Text(model) }
                            }
                        }
                        Divider()
                        Button("管理连接…") { openSettings() }
                    } label: {
                        Text(settings.config.model.isEmpty ? "选择模型" : settings.config.model).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true).disabled(viewModel.isStreaming)
                }
                Spacer(minLength: 8)
                Button { showHistory.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }.help("此 PDF 的对话历史")
                    .popover(isPresented: $showHistory) {
                        HistoryListView(history: historyStore, model: viewModel, dismiss: { showHistory = false }).frame(width: 340, height: 380)
                    }
                Button { viewModel.newConversation() } label: { Image(systemName: "square.and.pencil") }.help("新对话（⌘N）")
                Button { openSettings() } label: { Image(systemName: "slider.horizontal.3") }.help("连接与偏好设置")
            }.buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 15)
            Divider().opacity(0.6)
            MessageListView(viewModel: viewModel, contextStore: contextStore)
            if viewModel.isStreaming {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(viewModel.activity).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                }.padding(.horizontal, 20).padding(.vertical, 6)
            }
            ChatInputView(viewModel: viewModel, contextStore: contextStore)
                .padding(.horizontal, 14).padding(.bottom, 10)
            HStack(spacing: 8) {
                Menu {
                    Toggle("允许文档工具", isOn: configBinding(\.toolsEnabled, fallback: true))
                    Toggle("允许联网", isOn: configBinding(\.webEnabled, fallback: false))
                    Toggle("允许页面图像工具", isOn: configBinding(\.visionEnabled, fallback: true))
                    Divider()
                    Menu("推理强度") {
                        ForEach(ReasoningEffort.allCases) { effort in
                            Button(effort.label) { settings.config.reasoningEffort = effort == .unset ? nil : effort.rawValue; settings.save() }
                        }
                    }
                    Button("配置网络搜索…") { openSettings() }
                } label: {
                    Label(settings.config.webEnabled == true ? "工具 · 联网已开" : "阅读工具", systemImage: settings.config.webEnabled == true ? "globe" : "wrench.and.screwdriver")
                        .font(.system(size: 11))
                }.menuStyle(.borderlessButton).fixedSize().disabled(viewModel.isStreaming)
                Spacer()
                Button { showStats.toggle() } label: { Image(systemName: "chart.bar.xaxis") }.buttonStyle(.plain).help("会话用量")
                    .popover(isPresented: $showStats) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("会话用量").font(.headline)
                            Text("输入 \(viewModel.sessionPromptTokens.formatted()) · 输出 \(viewModel.sessionCompletionTokens.formatted()) tokens")
                            Text(settings.config.pricing[settings.config.model] == nil ? "当前模型未配置价格" : String(format: "模型费用估算 $%.4f", viewModel.sessionCost))
                            Text("依赖服务商返回的用量；不包含联网搜索等工具费用。") .font(.caption).foregroundStyle(.secondary)
                        }.padding(18).frame(width: 290)
                    }
                Text("↵ 发送 · ⇧↵ 换行").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 18).padding(.bottom, 12)
            if let error = historyStore.persistenceError { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
        }.background(Color(NSColor.windowBackgroundColor))
    }
    private func configBinding(_ key: WritableKeyPath<APIConfig, Bool?>, fallback: Bool) -> Binding<Bool> {
        Binding(get: { settings.config[keyPath: key] ?? fallback }, set: { settings.config[keyPath: key] = $0; settings.save() })
    }
}
private struct HistoryListView: View {
    @ObservedObject var history: ConversationHistoryStore
    @ObservedObject var model: ChatViewModel
    var dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading) {
            Text("这份 PDF 的对话").font(.headline).padding(16)
            if history.conversations.isEmpty {
                ContentUnavailableView("还没有历史对话", systemImage: "bubble.left.and.bubble.right", description: Text("对话会自动保存在这台 Mac 上。"))
            } else {
                List(history.conversations) { conversation in
                    HStack {
                        Button {
                            model.stop()
                            model.restore(messages: history.load(conversation)); dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conversation.title).lineLimit(2)
                                Text(conversation.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button {
                            if history.currentConversationID == conversation.id { model.newConversation() }
                            history.delete(conversation)
                        } label: { Image(systemName: "trash").foregroundStyle(.secondary) }.buttonStyle(.borderless).help("删除对话")
                    }.padding(.vertical, 5)
                }.listStyle(.plain)
            }
        }
    }
}
