import Foundation
import SwiftUI

struct ChatMessage: Identifiable {
    var id: UUID = UUID()
    let role: String           // "user" | "assistant" | "system"(unused display)
    var text: String
    var images: [ChatImage]
    var usage: ChatUsage?
    var costUSD: Double?
    var streaming: Bool
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var pendingImages: [ChatImage] = []
    @Published var isStreaming: Bool = false
    @Published var error: String?
    @Published var currentModel: String

    // 当前会话累计统计
    @Published var sessionPromptTokens: Int = 0
    @Published var sessionCompletionTokens: Int = 0
    @Published var sessionCost: Double = 0

    private var streamTask: Task<Void, Never>?

    /// 对话历史持久化；由 ContentView 在 PDF 加载时注入。
    var history: ConversationHistoryStore?

    // 流式增量缓冲：每 120ms 合并刷新一次，降低高频发布导致的掉帧
    private var pendingDeltas: [UUID: String] = [:]
    private var flushScheduled = false

    let settings = AppSettings.shared

    init() {
        currentModel = AppSettings.shared.config.model
    }

    var sessionTotalTokens: Int { sessionPromptTokens + sessionCompletionTokens }

    func newConversation() {
        streamTask?.cancel()
        history?.beginNewConversation()
        messages = []
        inputText = ""
        pendingImages = []
        isStreaming = false
        error = nil
        sessionPromptTokens = 0
        sessionCompletionTokens = 0
        sessionCost = 0
    }

    /// 从历史记录恢复一段对话（会保持其 id，便于后续保存更新同一条目）。
    func restore(messages restored: [ChatMessage]) {
        streamTask?.cancel()
        pendingDeltas.removeAll()
        flushScheduled = false
        messages = restored
        inputText = ""
        pendingImages = []
        isStreaming = false
        error = nil
        sessionPromptTokens = 0
        sessionCompletionTokens = 0
        sessionCost = 0
    }

    /// 把当前消息同步到持久化历史（过滤掉尚未收到任何内容的流式占位）。
    private func syncHistory() {
        history?.saveCurrent(messages: messages)
    }

    /// 缓冲流式增量，按固定间隔合并写入，避免每个 token 都触发整表刷新。
    private func bufferDelta(_ delta: String, assistantId: UUID) {
        pendingDeltas[assistantId, default: ""] += delta
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self else { return }
            self.flushScheduled = false
            var appendedAfterStop = false
            for (id, text) in self.pendingDeltas {
                if let idx = self.messages.firstIndex(where: { $0.id == id }) {
                    self.messages[idx].text += text
                    if !self.messages[idx].streaming { appendedAfterStop = true }
                }
            }
            self.pendingDeltas.removeAll()
            if appendedAfterStop { self.syncHistory() }
        }
    }

    func switchModel(_ model: String) {
        currentModel = model
        settings.config.model = model
        settings.save()
    }

    func addImage(_ img: ChatImage) {
        pendingImages.append(img)
    }

    func removeImage(at index: Int) {
        guard pendingImages.indices.contains(index) else { return }
        pendingImages.remove(at: index)
    }

    /// 发送当前输入。context 由 store 提供。
    func send(contextStore: PDFContextStore) {
        guard !isStreaming else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty else { return }

        let userImages = pendingImages
        let userMsg = ChatMessage(role: "user", text: text, images: userImages, usage: nil, costUSD: nil, streaming: false)
        messages.append(userMsg)
        inputText = ""
        pendingImages = []

        // assistant 占位
        let assistant = ChatMessage(role: "assistant", text: "", images: [], usage: nil, costUSD: nil, streaming: true)
        let assistantId = assistant.id
        messages.append(assistant)
        syncHistory()

        let systemPrompt = Self.buildSystemPrompt(contextText: contextStore.contextText)

        // 历史（不含刚加的 assistant 占位）
        let history: [(role: String, text: String, images: [ChatImage])] =
            messages.dropLast().map { (role: $0.role, text: $0.text, images: $0.images) }

        isStreaming = true
        error = nil

        let cfg = settings.config
        let key = settings.apiKey
        let model = currentModel
        let client = OpenAIClient(baseURL: cfg.baseURL, apiKey: key, model: model, reasoningEffort: cfg.reasoningEffort)
        let price = settings.price(for: model)

        let onDelta: (String) -> Void = { [weak self] delta in
            Task { @MainActor in
                self?.bufferDelta(delta, assistantId: assistantId)
            }
        }
        let onUsage: (ChatUsage) -> Void = { [weak self] usage in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let idx = self.messages.firstIndex(where: { $0.id == assistantId }) else { return }
                self.messages[idx].usage = usage
                let cost = Double(usage.promptTokens) * price.inputPerMillion / 1_000_000
                      + Double(usage.completionTokens) * price.outputPerMillion / 1_000_000
                self.messages[idx].costUSD = cost
                self.sessionPromptTokens += usage.promptTokens
                self.sessionCompletionTokens += usage.completionTokens
                self.sessionCost += cost
                self.syncHistory()
            }
        }

        streamTask = Task { [weak self] in
            do {
                try await client.streamChat(
                    systemPrompt: systemPrompt,
                    history: history,
                    onDelta: onDelta,
                    onUsage: onUsage
                )
                await MainActor.run {
                    if let idx = self?.messages.firstIndex(where: { $0.id == assistantId }) {
                        self?.messages[idx].streaming = false
                    }
                    self?.syncHistory()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                        self.messages[idx].streaming = false
                        if self.messages[idx].text.isEmpty {
                            self.messages[idx].text = "（出错）\(error.localizedDescription)"
                        }
                    }
                    self.error = error.localizedDescription
                    self.syncHistory()
                }
            }
            await MainActor.run { self?.isStreaming = false }
        }
    }

    func stop() {
        streamTask?.cancel()
        isStreaming = false
        for i in messages.indices where messages[i].streaming { messages[i].streaming = false }
        syncHistory()
    }

    private static func buildSystemPrompt(contextText: String) -> String {
        let trimmed = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        let preamble = """
        你是一个 PDF 阅读助手，工作在 macOS 应用中，目标是为用户在阅读 PDF 时提供帮助。你的回答须基于事实、力求客观准确。不要刻意迎合用户，也不要刻意反驳用户；遇到不确定或上下文未覆盖之处，请如实说明，而非臆测或编造。
        """
        if trimmed.isEmpty {
            return preamble + "用户可能就一份 PDF 向你提问，当前暂无可用上下文，请基于常识作答并明确提示缺乏来源依据。"
        }
        return preamble + "以下是用户当前关注的上下文（PDF 全文或选区），请基于它回答问题：\n\n" + trimmed + "\n\n若上下文未覆盖该问题，请如实说明。"
    }
}