import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var apiKeyInput: String = ""
    @State private var modelsText: String = ""

    var body: some View {
        TabView {
            apiTab.tabItem { Label("API", systemImage: "key") }
            pricingTab.tabItem { Label("价格", systemImage: "dollarsign.circle") }
            presetsTab.tabItem { Label("预置提示词", systemImage: "text.bubble") }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            apiKeyInput = settings.apiKey
            modelsText = settings.config.models.joined(separator: "\n")
        }
    }

    // MARK: API
    private var apiTab: some View {
        Form {
            Section("服务商预设") {
                HStack {
                    Menu("选择以填充 baseURL") {
                        ForEach(ProviderPresets.all) { p in
                            Button(p.name) {
                                settings.config.baseURL = p.baseURL
                                if !settings.config.models.contains(p.defaultModel) {
                                    settings.config.models.insert(p.defaultModel, at: 0)
                                    modelsText = settings.config.models.joined(separator: "\n")
                                }
                                settings.save()
                            }
                        }
                    }
                    Spacer()
                }
            }
            Section("接口配置") {
                TextField("BaseURL（OpenAI 兼容，到 /v1）", text: $settings.config.baseURL)
                SecureField("API Key（存入 Keychain）", text: $apiKeyInput)
                    .onChange(of: apiKeyInput) { _, v in settings.apiKey = v }
            }
            Section("模型列表（每行一个）") {
                TextEditor(text: $modelsText)
                    .frame(height: 100)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: modelsText) { _, v in
                        settings.config.models = v
                            .split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        settings.save()
                    }
                Picker("当前模型", selection: Binding(
                    get: { settings.config.model },
                    set: { settings.config.model = $0; settings.save() }
                )) {
                    ForEach(settings.config.models, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Pricing
    private var pricingTab: some View {
        Form {
            Section("每个模型的输入/输出单价（美元 / 1M tokens）") {
                ForEach(settings.config.models, id: \.self) { model in
                    pricingRow(for: model)
                }
            }
            Section("上下文上限") {
                ForEach(settings.config.models, id: \.self) { model in
                    HStack {
                        Text(model).frame(width: 160, alignment: .leading)
                        TextField("max context tokens",
                                  text: Binding(
                                    get: { settings.config.maxContexts[model]?.description ?? "128000" },
                                    set: { settings.config.maxContexts[model] = Int($0) ?? 128000; settings.save() }
                                  ))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func pricingRow(for model: String) -> some View {
        let price = settings.config.pricing[model] ?? ModelPrice(inputPerMillion: 0, outputPerMillion: 0)
        return HStack {
            Text(model).frame(width: 160, alignment: .leading)
            TextField("输入 $/1M",
                      text: Binding(
                        get: { String(price.inputPerMillion) },
                        set: {
                            let v = Double($0) ?? 0
                            var p = settings.config.pricing[model] ?? ModelPrice(inputPerMillion: 0, outputPerMillion: 0)
                            p.inputPerMillion = v
                            settings.config.pricing[model] = p
                            settings.save()
                        }
                      ))
            TextField("输出 $/1M",
                      text: Binding(
                        get: { String(price.outputPerMillion) },
                        set: {
                            let v = Double($0) ?? 0
                            var p = settings.config.pricing[model] ?? ModelPrice(inputPerMillion: 0, outputPerMillion: 0)
                            p.outputPerMillion = v
                            settings.config.pricing[model] = p
                            settings.save()
                        }
                      ))
        }
    }

    // MARK: Presets
    private var presetsTab: some View {
        PresetPromptsView()
    }
}