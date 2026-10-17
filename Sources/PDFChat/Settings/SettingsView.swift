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
            connectionTab.tabItem { Label("Connections", systemImage: "network") }
            readingTab.tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            pricingTab.tabItem { Label("Usage", systemImage: "chart.bar") }
            PresetPromptsView().padding(16).tabItem { Label("Prompts", systemImage: "text.badge.star") }
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
                    Picker("Connections", selection: Binding(get: { settings.activeProfileID }, set: { settings.select($0) })) {
                        ForEach(settings.profiles) { profile in Text(profile.name).tag(profile.id) }
                    }.disabled(busy)
                    Button { settings.addConnection() } label: { Image(systemName: "plus") }.disabled(busy).help("Add connection")
                    Button { settings.removeConnection() } label: { Image(systemName: "minus") }.disabled(settings.profiles.count < 2 || busy)
                }
                TextField("Name", text: $name).onChange(of: name) { _, value in settings.rename(value) }
            } header: { Text("Custom API") } footer: { Text("Each connection has its own endpoint, models, and API key. Keys are stored in macOS Keychain.") }
            Section {
                HStack {
                    Text("Quick setup")
                    Spacer()
                    Menu("Choose provider") {
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
                TextField("Base URL", text: $settings.config.baseURL, prompt: Text("https://api.example.com/v1"))
                SecureField("API Key", text: $apiKey).onChange(of: apiKey) { _, value in settings.apiKey = value }
                Picker("API protocol", selection: Binding(get: { settings.config.resolvedStyle }, set: { settings.config.apiStyle = $0 })) {
                    ForEach(APIStyle.allCases) { style in Text(style.label).tag(style) }
                }
            } footer: { Text("Full PDF is the default. Your provider and model must support file inputs. Otherwise, switch to PDFKit Text in the composer. Local endpoints can use an empty API key.") }
            Section("Models") {
                TextField("Model ID", text: $settings.config.model)
                TextField("Other models (comma-separated)", text: $modelsText)
                    .onChange(of: modelsText) { _, value in
                        settings.config.models = value.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }
                HStack {
                    Button("Fetch models") { fetchModels() }.disabled(busy)
                    Button("Test connection") { testConnection() }.disabled(busy || settings.config.model.isEmpty)
                    if busy { ProgressView().controlSize(.small) }
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(succeeded ? Color.secondary : Color.red).textSelection(.enabled) }
            }
        }.formStyle(.grouped)
    }
    private var readingTab: some View {
        Form {
            Section("Document tools") {
                Toggle("Allow PDF search and page reading", isOn: flag(\.toolsEnabled, fallback: true))
                Toggle("Allow page images", isOn: flag(\.visionEnabled, fallback: true))
                Text("Page images require a vision model. Document tools access only the current PDF and do not modify it.") .font(.caption).foregroundStyle(.secondary)
            }
            Section("Web search") {
                Toggle("Allow web search and page reading", isOn: flag(\.webEnabled, fallback: false))
                SecureField("Brave Search API key (optional)", text: $searchKey).onChange(of: searchKey) { _, value in settings.searchKey = value }
                Text("Responses uses the provider's built-in web_search when supported. Chat Completions uses Brave Search with a separate key. Enable document tools to also read public webpages.") .font(.caption).foregroundStyle(.secondary)
                Link("Brave Search API documentation", destination: URL(string: "https://api-dashboard.search.brave.com/app/documentation/web-search/get-started")!)
            }
            Section("Compatibility") {
                Toggle("Request streamed token usage", isOn: flag(\.includeUsage, fallback: true))
                Picker("Reasoning effort", selection: Binding(get: { ReasoningEffort(string: settings.config.reasoningEffort) }, set: { settings.config.reasoningEffort = $0 == .unset ? nil : $0.rawValue })) {
                    ForEach(ReasoningEffort.allCases) { effort in Text(effort.label).tag(effort) }
                }
                Text("Keep reasoning effort at Default if unsure. Disable tools or streamed usage if your provider rejects those parameters.") .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var pricingTab: some View {
        Form {
            Section("Current model") {
                Text(settings.config.model).font(.headline)
                TextField("Context limit (tokens)", text: Binding(get: { String(settings.maxContext(for: settings.config.model)) }, set: { if let value = Int($0), value > 0 { settings.config.maxContexts[settings.config.model] = value } }))
                Text("Text mode estimates document and chat length before sending. PDF image usage is determined by the provider.") .font(.caption).foregroundStyle(.secondary)
            }
            Section("Model pricing · USD per million tokens") {
                priceField("Input", input: true)
                priceField("Output", input: false)
                Button("Clear model pricing") { settings.config.pricing.removeValue(forKey: settings.config.model) }
                Text("Unconfigured prices are not treated as free. Estimates exclude search, cache pricing, and other provider fees.") .font(.caption).foregroundStyle(.secondary)
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
        }), prompt: Text("Not configured"))
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
                succeeded = true; status = models.isEmpty ? "No models returned. Enter a model ID manually." : "Fetched \(models.count) models."
            } catch { succeeded = false; status = error.localizedDescription }
        }
    }
    private func testConnection() {
        busy = true; status = ""
        let client = OpenAIClient(config: settings.config, apiKey: settings.apiKey)
        Task {
            defer { busy = false }
            do { try await client.testConnection(); succeeded = true; status = "Connected successfully. PDF and tool support depend on the selected model." }
            catch { succeeded = false; status = error.localizedDescription }
        }
    }
}
