import SwiftUI

// MARK: - Focused values（用于菜单命令定位当前活跃窗口）
private struct ChatViewModelKey: FocusedValueKey { typealias Value = ChatViewModel }
private struct OpenFilePickerKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var pdfChatViewModel: ChatViewModel? {
        get { self[ChatViewModelKey.self] }
        set { self[ChatViewModelKey.self] = newValue }
    }
    var pdfChatOpenPicker: (() -> Void)? {
        get { self[OpenFilePickerKey.self] }
        set { self[OpenFilePickerKey.self] = newValue }
    }
}

@main
struct PDFChatApp: App {
    @FocusedValue(\.pdfChatViewModel) private var chatVM: ChatViewModel?
    @FocusedValue(\.pdfChatOpenPicker) private var openPicker: (() -> Void)?

    var body: some Scene {
        // 文档驱动的多窗口场景：Finder 双击 PDF / 拖入 / 应用内打开
        // 都会通过 SwiftUI 的文档架构为每个 PDF 创建独立窗口。
        DocumentGroup(viewing: PDFFileDocument.self) { file in
            ContentView(pdfDoc: file.$document.pdfDocument)
        }
        .commands { appCommands }

        // 兜底欢迎窗口：Dock 启动（无文档）时显示一个空白窗口。
        // 顺序关键：放在 DocumentGroup 之后，文档冷启动仍优先路由到上面的文档场景。
        WindowGroup("PDFChat") {
            ContentView(pdfDoc: .constant(nil))
        }

        Settings {
            SettingsView()
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新对话") { chatVM?.newConversation() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(chatVM == nil)

            Button("打开 PDF…") { openPicker?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(openPicker == nil)
        }
    }
}