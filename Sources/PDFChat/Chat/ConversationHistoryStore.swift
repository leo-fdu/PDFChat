import Foundation
import CryptoKit
import SwiftUI

/// 可持久化的单条消息。
struct StoredChatMessage: Codable {
    var id: UUID
    var role: String
    var text: String
    var imageDataURLs: [String]
    var promptTokens: Int?
    var completionTokens: Int?
    var costUSD: Double?
}

/// 一段完整对话（对应对话历史列表中的一项）。
struct StoredConversation: Codable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [StoredChatMessage]
}

/// 按 PDF 文件持久化对话历史。
/// 每个 PDF 对应 Application Support/PDFChat/History/<sha256(path)>.json，
/// 文件内为该 PDF 的全部历史对话（按更新时间倒序）。
@MainActor
final class ConversationHistoryStore: ObservableObject {
    @Published private(set) var conversations: [StoredConversation] = []
    /// 当前正在进行的会话 id；nil 表示「新对话」，首次保存时会创建新条目。
    @Published private(set) var currentConversationID: UUID?

    private(set) var storageKey: String?

    static var historyDirectory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("PDFChat/History", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 由 PDF 绝对路径派生存储键（无 URL 的临时文档不持久化）。
    static func storageKey(for url: URL?) -> String? {
        guard let url else { return nil }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard !path.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var fileURL: URL? {
        guard let key = storageKey, let dir = Self.historyDirectory else { return nil }
        return dir.appendingPathComponent(key + ".json")
    }

    /// 加载指定 PDF 的历史对话（覆盖当前内容）。
    func load(for pdfURL: URL?) {
        storageKey = Self.storageKey(for: pdfURL)
        conversations = []
        currentConversationID = nil
        guard let file = fileURL,
              let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([StoredConversation].self, from: data) else { return }
        conversations = list.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 把当前消息列表同步为一条会话并写盘。
    /// currentConversationID 为 nil 时新建条目（即「新对话」的第一次保存）。
    func saveCurrent(messages: [ChatMessage]) {
        guard storageKey != nil else { return }
        let visible = messages.filter { !($0.streaming && $0.text.isEmpty) }
        guard visible.contains(where: { !$0.text.isEmpty || !$0.images.isEmpty }) else { return }
        let stored = visible.map { m in
            StoredChatMessage(
                id: m.id,
                role: m.role,
                text: m.text,
                imageDataURLs: m.images.map(\.dataURL),
                promptTokens: m.usage?.promptTokens,
                completionTokens: m.usage?.completionTokens,
                costUSD: m.costUSD
            )
        }
        let now = Date()
        if let id = currentConversationID,
           let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].messages = stored
            conversations[idx].title = Self.title(for: stored)
            conversations[idx].updatedAt = now
        } else {
            let conv = StoredConversation(id: UUID(), title: Self.title(for: stored),
                                          createdAt: now, updatedAt: now, messages: stored)
            currentConversationID = conv.id
            conversations.insert(conv, at: 0)
        }
        persist()
    }

    /// 「新对话」：当前条目保留在历史中，后续保存会另起一条。
    func beginNewConversation() {
        currentConversationID = nil
    }

    /// 选中一条历史对话，返回可恢复的 ChatMessage 列表，并将其设为当前会话。
    func load(_ conversation: StoredConversation) -> [ChatMessage] {
        currentConversationID = conversation.id
        return conversation.messages.map { m in
            ChatMessage(
                id: m.id,
                role: m.role,
                text: m.text,
                images: m.imageDataURLs.map { ChatImage(dataURL: $0, thumbData: Self.thumbData(fromDataURL: $0)) },
                usage: m.promptTokens.map {
                    ChatUsage(promptTokens: $0, completionTokens: m.completionTokens ?? 0,
                              totalTokens: $0 + (m.completionTokens ?? 0))
                },
                costUSD: m.costUSD,
                streaming: false
            )
        }
    }

    func delete(_ conversation: StoredConversation) {
        conversations.removeAll { $0.id == conversation.id }
        if currentConversationID == conversation.id { currentConversationID = nil }
        persist()
    }

    private func persist() {
        guard let file = fileURL else { return }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func title(for messages: [StoredChatMessage]) -> String {
        let t = (messages.first { $0.role == "user" }?.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(24)) }
        return "图片对话"
    }

    private static func thumbData(fromDataURL url: String) -> Data? {
        guard url.hasPrefix("data:"), let comma = url.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(url[url.index(after: comma)...]))
    }
}
