import Foundation

/// 单个 provider 预设（仅用于设置页快速填充 baseURL）。
struct ProviderPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseURL: String
    let defaultModel: String
}

enum ProviderPresets {
    static let all: [ProviderPreset] = [
        .init(name: "OpenAI",   baseURL: "https://api.openai.com/v1",            defaultModel: "gpt-4o-mini"),
        .init(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1",         defaultModel: "deepseek-chat"),
        .init(name: "Moonshot", baseURL: "https://api.moonshot.cn/v1",          defaultModel: "moonshot-v1-8k"),
        .init(name: "智谱 GLM",  baseURL: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4-flash"),
        .init(name: "SiliconFlow", baseURL: "https://api.siliconflow.cn/v1",    defaultModel: "Qwen/Qwen2.5-7B-Instruct")
    ]
}

/// API 与偏好配置（单一配置，通过 UserDefaults 持久化）。
struct APIConfig: Codable, Equatable {
    var baseURL: String
    var model: String
    /// 可切换模型列表（逗号或换行分隔后解析）。
    var models: [String]
    /// 每个模型的输入/输出单价（美元 / 1M tokens）。
    var pricing: [String: ModelPrice]
    /// 每个模型的最大上下文 token 数（用于超限预警）。
    var maxContexts: [String: Int]

    static func == (lhs: APIConfig, rhs: APIConfig) -> Bool {
        lhs.baseURL == rhs.baseURL && lhs.model == rhs.model && lhs.models == rhs.models
    }
}

struct ModelPrice: Codable, Equatable {
    var inputPerMillion: Double   // $/1M 输入 tokens
    var outputPerMillion: Double  // $/1M 输出 tokens
}

extension APIConfig {
    static let `default` = APIConfig(
        baseURL: "https://api.deepseek.com/v1",
        model: "deepseek-chat",
        models: ["deepseek-chat", "deepseek-reasoner"],
        pricing: [
            "deepseek-chat":   .init(inputPerMillion: 0.27, outputPerMillion: 1.10),
            "deepseek-reasoner": .init(inputPerMillion: 0.55, outputPerMillion: 2.19)
        ],
        maxContexts: [
            "deepseek-chat": 65536,
            "deepseek-reasoner": 65536
        ]
    )
}

/// 全局设置：负责把非密配置存 UserDefaults，apiKey 存 Keychain。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var config: APIConfig

    private let defaults = UserDefaults.standard
    private let configKey = "APIConfig.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: "APIConfig.v1"),
           let decoded = try? JSONDecoder().decode(APIConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
        }
    }

    var apiKey: String {
        get { KeychainStore.get("default") ?? "" }
        set { KeychainStore.set(newValue, for: "default") }
    }

    func save() {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: configKey)
        }
    }

    func price(for model: String) -> ModelPrice {
        config.pricing[model] ?? .init(inputPerMillion: 0, outputPerMillion: 0)
    }

    func maxContext(for model: String) -> Int {
        config.maxContexts[model] ?? 128_000
    }
}