import SwiftUI
import UniformTypeIdentifiers

struct ChatInputView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var slashStore: SlashCommandStore
    @ObservedObject var contextStore: PDFContextStore

    @State private var showFilePicker = false
    @State private var slashMatches: [PresetPrompt] = []
    @State private var slashOpen = false

    var body: some View {
        VStack(spacing: 8) {
            // 待发图片缩略图
            if !viewModel.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(viewModel.pendingImages.enumerated()), id: \.offset) { idx, img in
                            ZStack(alignment: .topTrailing) {
                                if let data = img.thumbData, let nsImg = NSImage(data: data) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                        .overlay(Image(systemName: "photo"))
                                }
                                Button {
                                    viewModel.removeImage(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.4)))
                                }
                                .buttonStyle(.plain)
                                .padding(2)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            ZStack(alignment: .topLeading) {
                ChatInputTextView(
                    text: $viewModel.inputText,
                    onSend: { viewModel.send(contextStore: contextStore) },
                    onPasteImage: { handleImage($0) },
                    onTextChange: { updateSlash() }
                )
                .frame(height: 64)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(nearLimitBorder())
            )

            // slash 补全下拉
            if slashOpen && !slashMatches.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(slashMatches) { p in
                        Button {
                            applyPreset(p)
                        } label: {
                            HStack {
                                Text("/\(p.trigger)").bold().foregroundColor(.accentColor)
                                Text(p.content.prefix(40))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .shadow(radius: 3)
            }

            HStack(spacing: 6) {
                Button {
                    showFilePicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                }
                .help("插入图片")

                Spacer()

                if viewModel.isStreaming {
                    Button {
                        viewModel.stop()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        showPreviewHint()
                    } label: {
                        Label("发送", systemImage: "paperplane.fill")
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for u in urls {
                    if let nsImg = NSImage(contentsOf: u) { handleImage(nsImg) }
                }
            case .failure: break
            }
        }
    }

    private func nearLimitBorder() -> Color {
        let limit = AppSettings.shared.maxContext(for: viewModel.currentModel)
        let total = contextStore.contextTokenCount + viewModel.sessionTotalTokens
        if total > Int(Double(limit) * 0.9) { return .orange }
        return Color.secondary.opacity(0.3)
    }

    private func updateSlash() {
        let t = viewModel.inputText
        if t.hasPrefix("/") && !t.contains(" ") && !t.contains("\n") {
            let m = slashStore.matches(for: t)
            slashMatches = m
            slashOpen = !m.isEmpty
        } else {
            slashOpen = false
            slashMatches = []
        }
    }

    private func applyPreset(_ p: PresetPrompt) {
        viewModel.inputText = p.content
        slashOpen = false
    }

    private func handleImage(_ nsImage: NSImage) {
        guard let dataURL = ImageCoding.dataURL(from: nsImage),
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        viewModel.addImage(ChatImage(dataURL: dataURL, thumbData: png))
    }

    private func showPreviewHint() {
        // 占位：真正发送通过输入框 Enter；该按钮也直接发送。
        viewModel.send(contextStore: contextStore)
    }
}