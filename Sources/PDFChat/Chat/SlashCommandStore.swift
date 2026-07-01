import Foundation

struct PresetPrompt: Codable, Identifiable, Hashable {
    var id: String { trigger }
    let trigger: String   // 例如 "总结"（不带 /）
    var content: String
}

@MainActor
final class SlashCommandStore: ObservableObject {
    static let shared = SlashCommandStore()

    @Published var presets: [PresetPrompt]
    private let key = "PresetPrompts.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: "PresetPrompts.v1"),
           let decoded = try? JSONDecoder().decode([PresetPrompt].self, from: data) {
            presets = decoded
        } else {
            presets = [
                .init(trigger: "总结", content: "请总结这段内容的核心要点，分条列出。"),
                .init(trigger: "翻译", content: "请将以下内容翻译为英文，仅输出译文。"),
                .init(trigger: "解释", content: "请用通俗易懂的语言解释以下内容，必要时举例。"),
                .init(trigger: "提取", content: "请从以下内容中提取关键实体（人名/术语/数字等），以表格呈现。"),
                .init(trigger: "改写", content: "请改写以下内容，使其更简洁清晰，保持原意。")
            ]
            save()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 输入文本行首为 `/xxx` 时，返回匹配的预设。
    func matches(for rawText: String) -> [PresetPrompt] {
        let text = rawText
        guard text.hasPrefix("/") else { return [] }
        let query = String(text.dropFirst()).lowercased()
        // 仅在行首、未含空格时触发
        if query.contains(" ") || query.contains("\n") { return [] }
        if query.isEmpty { return presets }
        return presets.filter { $0.trigger.lowercased().hasPrefix(query) }
    }
}