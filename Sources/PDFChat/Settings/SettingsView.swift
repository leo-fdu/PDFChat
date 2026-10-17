import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiKey = ""
    @State private var searchKey = ""
    @State private var name = ""
    @State private var modelsText = ""
    @State private var status = ""
    @State private var busy = false
    @State private var succeeded = false
    var body: some View {
        TabView {
            connectionTab.tabItem { Label("连接", systemImage: "network") }
            readingTab.tabItem { Label("工具", systemImage: "wrench.and.screwdriver") }
            pricingTab.tabItem { Label("用量", systemImage: "chart.bar") }
            PresetPromptsView().padding(16).tabItem { Label("快捷提示词", systemImage: "text.badge.star") }
        }
        .frame(width: 640, height: 630)
        .tint(Color(red: 0.34, green: 0.39, blue: 0.82))
        .onAppear { loadFields() }
        .onChange(of: settings.activeProfileID) { _, _ in loadFields() }
        .onChange(of: settings.config) { _, _ in settings.save() }
    }
    private var connectionTab: some View {
        Form {
            Section {
                HStack {
                    Picker("连接", selection: Binding(get: { settings.activeProfileID }, set: { settings.select($0) })) {
                        ForEach(settings.profiles) { profile in Text(profile.name).tag(profile.id) }
                    }.disabled(busy)
                    Button { settings.addConnection() } label: { Image(systemName: "plus") }.disabled(busy).help("新增独立连接")
                    Button { settings.removeConnection() } label: { Image(systemName: "minus") }.disabled(settings.profiles.count < 2 || busy)
                }
                TextField("名称", text: $name).onChange(of: name) { _, value in settings.rename(value) }
            } header: { Text("自定义 API") } footer: { Text("每个连接独立保存地址、模型与密钥。密钥存放于 macOS 钥匙串。") }
            Section {
                HStack {
                    Text("快速填写")
                    Spacer()
                    Menu("选择服务商") {
                        ForEach(ProviderPresets.all) { preset in
                            Button(preset.name) {
                                settings.config.baseURL = preset.baseURL
                                settings.config.models = [preset.defaultModel]
                                settings.config.model = preset.defaultModel
                                settings.config.apiStyle = preset.name == "OpenAI" ? .responses : .chatCompletions
                                settings.config.reasoningEffort = nil
                                modelsText = preset.defaultModel
                            }
                        }
                    }.fixedSize()
                }
                TextField("API 根地址", text: $settings.config.baseURL, prompt: Text("https://api.example.com/v1"))
                SecureField("API Key", text: $apiKey).onChange(of: apiKey) { _, value in settings.apiKey = value }
                Picker("接口协议", selection: Binding(get: { settings.config.resolvedStyle }, set: { settings.config.apiStyle = $0 })) {
                    ForEach(APIStyle.allCases) { style in Text(style.label).tag(style) }
                }
            } footer: { Text("默认发送完整 PDF。所选服务商和模型必须支持文件输入；不支持时可在聊天输入框切换「PDFKit 文字」。本地免密接口可以留空 API Key。") }
            Section("模型") {
                TextField("当前模型 ID", text: $settings.config.model)
                TextField("备选模型（逗号分隔）", text: $modelsText)
                    .onChange(of: modelsText) { _, value in
                        settings.config.models = value.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }
                HStack {
                    Button("获取模型列表") { fetchModels() }.disabled(busy)
                    Button("测试连接") { testConnection() }.disabled(busy || settings.config.model.isEmpty)
                    if busy { ProgressView().controlSize(.small) }
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(succeeded ? Color.secondary : Color.red).textSelection(.enabled) }
            }
        }.formStyle(.grouped)
    }
    private var readingTab: some View {
        Form {
            Section("文档工具") {
                Toggle("允许模型搜索和读取 PDF 页面", isOn: flag(\.toolsEnabled, fallback: true))
                Toggle("允许模型查看页面图像", isOn: flag(\.visionEnabled, fallback: true))
                Text("页面图像需要视觉模型。工具仅访问当前打开的 PDF，不会修改文件。") .font(.caption).foregroundStyle(.secondary)
            }
            Section("网络搜索") {
                Toggle("允许联网搜索与读取网页", isOn: flag(\.webEnabled, fallback: false))
                SecureField("Brave Search API Key（可选）", text: $searchKey).onChange(of: searchKey) { _, value in settings.searchKey = value }
                Text("Responses 模式使用服务商内置 web_search（服务商需支持）。兼容接口使用 Brave Search，需填写独立密钥。开启文档工具后，也可读取公开网页。") .font(.caption).foregroundStyle(.secondary)
                Link("Brave Search API 文档", destination: URL(string: "https://api-dashboard.search.brave.com/app/documentation/web-search/get-started")!)
            }
            Section("接口兼容性") {
                Toggle("请求流式 Token 用量", isOn: flag(\.includeUsage, fallback: true))
                Picker("推理强度", selection: Binding(get: { ReasoningEffort(string: settings.config.reasoningEffort) }, set: { settings.config.reasoningEffort = $0 == .unset ? nil : $0.rawValue })) {
                    ForEach(ReasoningEffort.allCases) { effort in Text(effort.label).tag(effort) }
                }
                Text("不确定模型能力时保留默认推理强度。如果接口拒绝工具或用量参数，可关闭对应选项。") .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var pricingTab: some View {
        Form {
            Section("当前模型") {
                Text(settings.config.model).font(.headline)
                TextField("上下文上限（tokens）", text: Binding(get: { String(settings.maxContext(for: settings.config.model)) }, set: { if let value = Int($0), value > 0 { settings.config.maxContexts[settings.config.model] = value } }))
                Text("文字模式发送前估算全文与聊天记录长度；PDF 图像用量由服务商决定。") .font(.caption).foregroundStyle(.secondary)
            }
            Section("模型单价 · 美元 / 百万 tokens") {
                priceField("输入", input: true)
                priceField("输出", input: false)
                Button("清除当前模型价格") { settings.config.pricing.removeValue(forKey: settings.config.model) }
                Text("未配置价格时不会把费用显示为免费。费用为估算，不包含搜索、缓存定价及其他服务商费用。") .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func priceField(_ title: String, input: Bool) -> some View {
        TextField(title, text: Binding(get: {
            guard let price = settings.config.pricing[settings.config.model] else { return "" }
            return String(input ? price.inputPerMillion : price.outputPerMillion)
        }, set: { raw in
            guard let value = Double(raw), value >= 0 else { return }
            var price = settings.config.pricing[settings.config.model] ?? .init(inputPerMillion: 0, outputPerMillion: 0)
            if input { price.inputPerMillion = value } else { price.outputPerMillion = value }
            settings.config.pricing[settings.config.model] = price
        }), prompt: Text("未配置"))
    }
    private func flag(_ key: WritableKeyPath<APIConfig, Bool?>, fallback: Bool) -> Binding<Bool> {
        Binding(get: { settings.config[keyPath: key] ?? fallback }, set: { settings.config[keyPath: key] = $0 })
    }
    private func loadFields() {
        apiKey = settings.apiKey; searchKey = settings.searchKey
        name = settings.connectionName; modelsText = settings.config.models.joined(separator: ", ")
        status = ""
    }
    private func fetchModels() {
        busy = true; status = ""
        let client = OpenAIClient(config: settings.config, apiKey: settings.apiKey)
        Task {
            defer { busy = false }
            do {
                let models = try await client.fetchModels()
                modelsText = models.joined(separator: ", ")
                succeeded = true; status = models.isEmpty ? "接口未返回模型，请手动填写模型 ID。" : "已获取 \(models.count) 个模型。"
            } catch { succeeded = false; status = error.localizedDescription }
        }
    }
    private func testConnection() {
        busy = true; status = ""
        let client = OpenAIClient(config: settings.config, apiKey: settings.apiKey)
        Task {
            defer { busy = false }
            do { try await client.testConnection(); succeeded = true; status = "连接成功，模型可用。PDF 和工具能力以实际请求为准。" }
            catch { succeeded = false; status = error.localizedDescription }
        }
    }
}
