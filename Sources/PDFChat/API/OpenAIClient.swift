import Foundation

struct ChatImage {
    let dataURL: String
    var thumbData: Data?
}
struct ChatUsage: Codable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
}
struct PDFInput: Sendable {
    let filename: String
    let base64: String
}
struct APIMessage {
    var role: String
    var text: String
    var images: [ChatImage] = []
}
struct ToolCall: Equatable {
    var id: String
    var name: String
    var arguments: String
}
struct ToolOutput {
    var text: String
    var imageURL: String? = nil
}
enum ChatEvent {
    case text(String), usage(ChatUsage), activity(String)
}
enum ChatError: LocalizedError {
    case configuration(String), server(Int, String), protocolError(String), toolLimit
    var errorDescription: String? {
        switch self {
        case .configuration(let s), .protocolError(let s): return s
        case .server(let code, let detail):
            let hint: String
            switch code {
            case 401, 403: hint = "鉴权失败，请检查当前连接的 API Key 与权限。"
            case 404: hint = "接口或模型不存在，请检查地址、协议和模型名称。"
            case 413: hint = "PDF 超过服务商的上传限制，可切换为文字模式。"
            case 429: hint = "请求限流或额度不足，请稍后重试。"
            default: hint = "服务商返回 HTTP \(code)。PDF 或工具不受支持时，请检查连接能力设置。"
            }
            return hint + (detail.isEmpty ? "" : "\n" + String(detail.prefix(1600)))
        case .toolLimit: return "已达到本次 12 轮工具调用上限，可以继续提问。"
        }
    }
}

/// One complete SSE event, including providers that split JSON over data lines.
struct SSEDecoder {
    private var dataLines: [String] = []
    mutating func consume(_ line: String) -> String? {
        if line.isEmpty { return finish() }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            dataLines.append(value)
        }
        return nil
    }
    mutating func finish() -> String? {
        guard !dataLines.isEmpty else { return nil }
        defer { dataLines.removeAll(keepingCapacity: true) }
        return dataLines.joined(separator: "\n")
    }
}

struct StreamRound {
    var text = ""
    var calls: [Int: ToolCall] = [:]
    var responseOutput: [[String: Any]] = []
    var finished = false

    mutating func accept(_ payload: String, style: APIStyle) throws -> [ChatEvent] {
        if payload == "[DONE]" { finished = true; return [] }
        guard let data = payload.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatError.protocolError("服务商返回了无法识别的流式数据。")
        }
        if let error = json["error"] as? [String: Any] {
            throw ChatError.protocolError(error["message"] as? String ?? "服务商返回错误。")
        }
        var events: [ChatEvent] = []
        if style == .responses {
            let type = json["type"] as? String ?? ""
            if type == "response.output_text.delta", let delta = json["delta"] as? String {
                text += delta; events.append(.text(delta))
            } else if type == "response.web_search_call.in_progress" {
                events.append(.activity("正在联网搜索"))
            } else if type == "response.output_item.done", let item = json["item"] as? [String: Any], item["type"] as? String == "function_call" {
                let index = json["output_index"] as? Int ?? calls.count
                calls[index] = ToolCall(id: item["call_id"] as? String ?? "", name: item["name"] as? String ?? "", arguments: item["arguments"] as? String ?? "{}")
            } else if type == "response.completed", let response = json["response"] as? [String: Any] {
                finished = true
                responseOutput = response["output"] as? [[String: Any]] ?? []
                // Preserve the exact completed output (including reasoning items) for tool continuation.
                for (index, item) in responseOutput.enumerated() where item["type"] as? String == "function_call" {
                    calls[index] = ToolCall(id: item["call_id"] as? String ?? "", name: item["name"] as? String ?? "", arguments: item["arguments"] as? String ?? "{}")
                }
                if let usage = response["usage"] as? [String: Any] { events.append(.usage(Self.usage(usage, responses: true))) }
                var links: [String] = []
                for item in responseOutput {
                    for part in item["content"] as? [[String: Any]] ?? [] {
                        for annotation in part["annotations"] as? [[String: Any]] ?? [] {
                            if annotation["type"] as? String == "url_citation", let url = annotation["url"] as? String,
                               let parsed = URL(string: url), ["https", "http"].contains(parsed.scheme ?? "") {
                                let title = (annotation["title"] as? String ?? parsed.host ?? "来源").replacingOccurrences(of: "]", with: "")
                                let link = "[\(title)](<\(url)>)"
                                if !links.contains(link) { links.append(link) }
                            }
                        }
                    }
                }
                if !links.isEmpty {
                    let citations = "\n\n来源：\n" + links.map { "- " + $0 }.joined(separator: "\n")
                    text += citations; events.append(.text(citations))
                }
            } else if ["response.failed", "response.incomplete", "error"].contains(type) {
                let response = json["response"] as? [String: Any] ?? json
                let error = response["error"] as? [String: Any]
                throw ChatError.protocolError(error?["message"] as? String ?? "响应未完成（可能达到输出上限），已保留收到的内容。")
            }
        } else {
            if let choices = json["choices"] as? [[String: Any]], let choice = choices.first {
                let delta = choice["delta"] as? [String: Any] ?? [:]
                if let value = delta["content"] as? String { text += value; events.append(.text(value)) }
                for item in delta["tool_calls"] as? [[String: Any]] ?? [] {
                    let index = item["index"] as? Int ?? 0
                    var call = calls[index] ?? ToolCall(id: "", name: "", arguments: "")
                    if let id = item["id"] as? String { call.id = id }
                    let function = item["function"] as? [String: Any] ?? [:]
                    if let name = function["name"] as? String { call.name += name }
                    if let args = function["arguments"] as? String { call.arguments += args }
                    calls[index] = call
                }
                if let reason = choice["finish_reason"] as? String {
                    if reason == "length" || reason == "content_filter" { throw ChatError.protocolError("回答被服务商提前截断（\(reason)），已保留收到的内容。") }
                    finished = true
                }
            }
            if let usage = json["usage"] as? [String: Any] { events.append(.usage(Self.usage(usage, responses: false))) }
        }
        return events
    }
    private static func usage(_ value: [String: Any], responses: Bool) -> ChatUsage {
        let input = value[responses ? "input_tokens" : "prompt_tokens"] as? Int ?? 0
        let output = value[responses ? "output_tokens" : "completion_tokens"] as? Int ?? 0
        return .init(promptTokens: input, completionTokens: output, totalTokens: input + output)
    }
}

final class OpenAIClient {
    let config: APIConfig
    let apiKey: String
    let session: URLSession
    init(config: APIConfig, apiKey: String, session: URLSession = .shared) {
        self.config = config; self.apiKey = apiKey; self.session = session
    }

    func endpoint(_ path: String) throws -> URL {
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme ?? ""), url.query == nil, url.fragment == nil else {
            throw ChatError.configuration("请输入有效的 API 根地址，例如 https://api.example.com/v1。")
        }
        return url.appendingPathComponent(path)
    }
    private func request(_ path: String, body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(path))
        request.timeoutInterval = 180
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func initialInput(style: APIStyle, system: String, messages: [APIMessage], pdf: PDFInput?) -> [[String: Any]] {
        var result: [[String: Any]] = [["role": "system", "content": system]]
        for (index, message) in messages.enumerated() {
            let attachPDF = index == messages.lastIndex(where: { $0.role == "user" }) ? pdf : nil
            if style == .responses {
                var parts: [[String: Any]] = []
                if let pdf = attachPDF { parts.append(["type": "input_file", "filename": pdf.filename, "file_data": "data:application/pdf;base64," + pdf.base64]) }
                if !message.text.isEmpty { parts.append(["type": message.role == "assistant" ? "output_text" : "input_text", "text": message.text]) }
                for image in message.images { parts.append(["type": "input_image", "image_url": image.dataURL]) }
                result.append(["role": message.role, "content": parts])
            } else {
                var parts: [[String: Any]] = []
                if let pdf = attachPDF { parts.append(["type": "file", "file": ["filename": pdf.filename, "file_data": "data:application/pdf;base64," + pdf.base64]]) }
                if !message.text.isEmpty { parts.append(["type": "text", "text": message.text]) }
                for image in message.images { parts.append(["type": "image_url", "image_url": ["url": image.dataURL]]) }
                if attachPDF == nil && message.images.isEmpty {
                    result.append(["role": message.role, "content": message.text])
                } else {
                    result.append(["role": message.role, "content": parts])
                }
            }
        }
        return result
    }

    func streamChat(system: String, messages: [APIMessage], pdf: PDFInput?, tools: [[String: Any]],
                    nativeWeb: Bool, execute: @escaping (ToolCall) async throws -> ToolOutput,
                    onEvent: @escaping (ChatEvent) async -> Void) async throws {
        let style = config.resolvedStyle
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatError.configuration("请先选择模型。") }
        var input = Self.initialInput(style: style, system: system, messages: messages, pdf: pdf)
        for _ in 0..<12 {
            try Task.checkCancellation()
            var body: [String: Any] = ["model": config.model, "stream": true]
            var declared = tools
            if style == .responses {
                body["input"] = input; body["store"] = false
                if nativeWeb { declared.append(["type": "web_search"]) }
                if let effort = config.reasoningEffort { body["reasoning"] = ["effort": effort] }
            } else {
                body["messages"] = input
                if config.includeUsage != false { body["stream_options"] = ["include_usage": true] }
                if let effort = config.reasoningEffort { body["reasoning_effort"] = effort }
            }
            if !declared.isEmpty { body["tools"] = declared }
            let req = try request(style == .responses ? "responses" : "chat/completions", body: body)
            let (bytes, response) = try await session.bytes(for: req)
            guard let http = response as? HTTPURLResponse else { throw ChatError.protocolError("无效的 HTTP 响应。") }
            guard (200..<300).contains(http.statusCode) else {
                var data = Data()
                for try await byte in bytes { data.append(byte); if data.count >= 8192 { break } }
                throw ChatError.server(http.statusCode, Self.errorDetail(data))
            }
            var decoder = SSEDecoder()
            var round = StreamRound()
            // AsyncBytes.lines drops blank lines on macOS; SSE requires them as
            // event boundaries. Decode UTF-8 lines from bytes without discarding blanks.
            var lineBytes = Data()
            for try await byte in bytes {
                if byte == 10 {
                    try Task.checkCancellation()
                    if lineBytes.last == 13 { lineBytes.removeLast() }
                    guard let line = String(data: lineBytes, encoding: .utf8) else { throw ChatError.protocolError("无效的 UTF-8 流。") }
                    lineBytes.removeAll(keepingCapacity: true)
                    if let payload = decoder.consume(line) {
                        for event in try round.accept(payload, style: style) { await onEvent(event) }
                        if payload == "[DONE]" || (style == .responses && round.finished) { break }
                    }
                } else {
                    lineBytes.append(byte)
                    if lineBytes.count > 8_000_000 { throw ChatError.protocolError("流式事件超过大小限制。") }
                }
            }
            if !lineBytes.isEmpty, let line = String(data: lineBytes, encoding: .utf8), let payload = decoder.consume(line) {
                for event in try round.accept(payload, style: style) { await onEvent(event) }
            }
            if let payload = decoder.finish() {
                for event in try round.accept(payload, style: style) { await onEvent(event) }
            }
            try Task.checkCancellation()
            guard round.finished else { throw ChatError.protocolError("连接在响应完成前中断，已保留收到的内容。") }
            let calls = round.calls.sorted { $0.key < $1.key }.map(\.value)
            if calls.isEmpty {
                guard !round.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatError.protocolError("模型返回了空回答，请检查模型与接口协议。") }
                return
            }
            guard calls.count <= 16 else { throw ChatError.protocolError("单轮工具调用过多。") }
            if style == .responses {
                input += round.responseOutput
            } else {
                input.append(["role": "assistant", "content": round.text,
                              "tool_calls": calls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]] }])
            }
            for call in calls {
                try Task.checkCancellation()
                await onEvent(.activity(ReadingTools.label(for: call.name)))
                let output = try await execute(call)
                if style == .responses {
                    input.append(["type": "function_call_output", "call_id": call.id, "output": output.text])
                } else {
                    input.append(["role": "tool", "tool_call_id": call.id, "content": output.text])
                }
                if let image = output.imageURL {
                    let part: [String: Any] = style == .responses ? ["type": "input_image", "image_url": image] : ["type": "image_url", "image_url": ["url": image]]
                    input.append(["role": "user", "content": [part]])
                }
            }
            if !round.text.isEmpty { await onEvent(.text("\n\n")) }
            await onEvent(.activity("正在整理回答"))
        }
        throw ChatError.toolLimit
    }

    func fetchModels() async throws -> [String] {
        let (data, response) = try await session.data(for: request("models"))
        try validate(response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.sorted()
    }
    func testConnection() async throws {
        let style = config.resolvedStyle
        let body: [String: Any] = style == .responses
            ? ["model": config.model, "input": "Reply OK.", "store": false, "max_output_tokens": 32]
            : ["model": config.model, "messages": [["role": "user", "content": "Reply OK."]], "max_tokens": 32]
        let (data, response) = try await session.data(for: request(style == .responses ? "responses" : "chat/completions", body: body))
        try validate(response, data: data)
    }
    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ChatError.protocolError("无效的响应。") }
        if !(200..<300).contains(http.statusCode) { throw ChatError.server(http.statusCode, Self.errorDetail(data)) }
    }
    static func errorDetail(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return String(data: data, encoding: .utf8).map { String($0.prefix(1600)) } ?? ""
    }
}
