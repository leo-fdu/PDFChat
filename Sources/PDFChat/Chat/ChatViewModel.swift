import Foundation
import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
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

    let settings = AppSettings.shared

    init() {
        currentModel = AppSettings.shared.config.model
    }

    var sessionTotalTokens: Int { sessionPromptTokens + sessionCompletionTokens }

    func newConversation() {
        streamTask?.cancel()
        messages = []
        inputText = ""
        pendingImages = []
        isStreaming = false
        error = nil
        sessionPromptTokens = 0
        sessionCompletionTokens = 0
        sessionCost = 0
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

        let systemPrompt = Self.buildSystemPrompt(contextText: contextStore.contextText)

        // 历史（不含刚加的 assistant 占位）
        let history: [(role: String, text: String, images: [ChatImage])] =
            messages.dropLast().map { (role: $0.role, text: $0.text, images: $0.images) }

        isStreaming = true
        error = nil

        let cfg = settings.config
        let key = settings.apiKey
        let model = currentModel
        let client = OpenAIClient(baseURL: cfg.baseURL, apiKey: key, model: model)
        let price = settings.price(for: model)

        let onDelta: (String) -> Void = { [weak self] delta in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let idx = self.messages.firstIndex(where: { $0.id == assistantId }) else { return }
                self.messages[idx].text += delta
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
                }
            }
            await MainActor.run { self?.isStreaming = false }
        }
    }

    func stop() {
        streamTask?.cancel()
        isStreaming = false
        for i in messages.indices where messages[i].streaming { messages[i].streaming = false }
    }

    private static func buildSystemPrompt(contextText: String) -> String {
        let trimmed = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "你是阅读助手。用户可能就一份 PDF 向你提问，暂无可用上下文，请基于常识作答。"
        }
        return "你是阅读助手。以下是用户当前关注的上下文（PDF 全文或选区），请基于它回答问题：\n\n" + trimmed + "\n\n若上下文未覆盖该问题，请如实说明。"
    }
}