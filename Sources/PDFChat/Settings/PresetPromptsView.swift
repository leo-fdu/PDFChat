import SwiftUI

struct PresetPromptsView: View {
    @ObservedObject var store = SlashCommandStore.shared
    @State private var newTrigger = ""
    @State private var newContent = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.presets) { p in
                    HStack(alignment: .top) {
                        Text("/\(p.trigger)").bold().foregroundColor(.accentColor)
                            .frame(width: 90, alignment: .leading)
                        TextField("", text: bindContent(for: p), axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(3...6)
                    }
                }
                .onDelete { store.presets.remove(atOffsets: $0); store.save() }
            }

            Divider()
            VStack(spacing: 6) {
                HStack {
                    TextField("触发词（如 总结）", text: $newTrigger)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        add()
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .disabled(newTrigger.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                TextField("提示词内容", text: $newContent, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            .padding(10)
        }
    }

    private func bindContent(for p: PresetPrompt) -> Binding<String> {
        Binding(
            get: { p.content },
            set: {
                if let idx = store.presets.firstIndex(where: { $0.id == p.id }) {
                    store.presets[idx].content = $0
                    store.save()
                }
            }
        )
    }

    private func add() {
        let t = newTrigger.trimmingCharacters(in: .whitespaces)
        let c = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let idx = store.presets.firstIndex(where: { $0.trigger == t }) {
            store.presets[idx].content = c
        } else {
            store.presets.append(.init(trigger: t, content: c.isEmpty ? "（待填写）" : c))
        }
        store.save()
        newTrigger = ""
        newContent = ""
    }
}