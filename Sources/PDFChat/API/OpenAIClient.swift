import Foundation

struct ChatImage {
    /// data: URL (data:image/png;base64,...) 或 https URL
    let dataURL: String
    /// 用于 UI 显示的缩略图 NSImage（运行时由 AppKit 生成）
    var thumbData: Data?
}

struct ChatUsage {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
}

enum ChatError: LocalizedError {
    case noConfig
    case badResponse(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noConfig: return "请先在设置中配置 API（baseURL / apiKey / model）。"
        case .badResponse(let m): return "响应解析失败：\(m)"
        case .http(let c): return "HTTP 错误：\(c)"
        }
    }
}

/// OpenAI 兼容的流式聊天客户端。
final class OpenAIClient {
    let baseURL: String
    let apiKey: String
    let model: String

    init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    /// 构造请求体。
    private func makeBody(messages: [[String: Any]], stream: Bool) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": stream
        ]
        if stream {
            body["stream_options"] = ["include_usage": true]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// 流式发送：对每个增量文本片段与最终 usage 调用回调。
    func streamChat(
        systemPrompt: String,
        history: [(role: String, text: String, images: [ChatImage])],
        onDelta: @escaping (String) -> Void,
        onUsage: @escaping (ChatUsage) -> Void
    ) async throws {
        guard !apiKey.isEmpty, !baseURL.isEmpty else { throw ChatError.noConfig }

        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for m in history {
            if m.images.isEmpty {
                messages.append(["role": m.role, "content": m.text])
            } else {
                var content: [[String: Any]] = [["type": "text", "text": m.text]]
                for img in m.images {
                    content.append([
                        "type": "image_url",
                        "image_url": ["url": img.dataURL]
                    ])
                }
                messages.append(["role": m.role, "content": content])
            }
        }

        var trimmed = baseURL
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        let url = URL(string: trimmed)!.appendingPathComponent("chat/completions")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try makeBody(messages: messages, stream: true)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // 尝试读取错误体
            var errText = ""
            for try await line in bytes.lines { errText += line }
            throw ChatError.http(http.statusCode)
        }

        for try await raw in bytes.lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { return }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // 解析增量文本
            if let choices = json["choices"] as? [[String: Any]],
               let choice = choices.first,
               let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                onDelta(content)
            }
            // 解析 usage（流式 usage 通常在最后一个空 choices 帧中）
            if let usage = json["usage"] as? [String: Any] {
                let u = ChatUsage(
                    promptTokens: usage["prompt_tokens"] as? Int ?? 0,
                    completionTokens: usage["completion_tokens"] as? Int ?? 0,
                    totalTokens: usage["total_tokens"] as? Int ?? 0
                )
                if u.totalTokens > 0 { onUsage(u) }
            }
        }
    }
}