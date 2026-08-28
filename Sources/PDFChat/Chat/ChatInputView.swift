import SwiftUI
import UniformTypeIdentifiers

/// 输入面板：唯一的根视图是铺满整个矩形的 SendableTextView，
/// 待发图片与 slash 补全均为悬浮层，面板内不存在任何内层视图边界。
struct ChatInputView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var slashStore: SlashCommandStore
    @ObservedObject var contextStore: PDFContextStore

    @State private var slashMatches: [PresetPrompt] = []
    @State private var slashOpen = false

    /// 有悬浮图片行时，文字顶部内边距加大到图片下方
    private var textTopInset: CGFloat {
        viewModel.pendingImages.isEmpty ? 12 : 76
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ChatInputTextView(
                text: $viewModel.inputText,
                topInset: textTopInset,
                onSend: { viewModel.send(contextStore: contextStore) },
                onPasteImage: { handleImage($0) },
                onTextChange: { updateSlash() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 悬浮层 1：待发图片缩略图（钉在矩形左上角）
            if !viewModel.pendingImages.isEmpty {
                pendingImagesRow
            }

            // 悬浮层 2：slash 补全下拉（钉在矩形左下角）
            if slashOpen && !slashMatches.isEmpty {
                slashDropdown
            }
        }
    }

    // MARK: - 悬浮层

    private var pendingImagesRow: some View {
        // 用 HStack 贴合内容宽度：缩略图之外的空白区域点击可穿透到文本框
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
        .padding(.leading, 8)
        .padding(.top, 6)
    }

    private var slashDropdown: some View {
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
        .padding(.leading, 8)
        .padding(.bottom, 8)
    }

    // MARK: - 逻辑

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
}
