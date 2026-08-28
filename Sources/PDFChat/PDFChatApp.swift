import SwiftUI

// MARK: - Focused values（用于菜单命令定位当前活跃窗口）
private struct ChatViewModelKey: FocusedValueKey { typealias Value = ChatViewModel }
private struct OpenFilePickerKey: FocusedValueKey { typealias Value = () -> Void }
private struct UndoHighlightKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var pdfChatViewModel: ChatViewModel? {
        get { self[ChatViewModelKey.self] }
        set { self[ChatViewModelKey.self] = newValue }
    }
    var pdfChatOpenPicker: (() -> Void)? {
        get { self[OpenFilePickerKey.self] }
        set { self[OpenFilePickerKey.self] = newValue }
    }
    var pdfChatUndoHighlight: (() -> Void)? {
        get { self[UndoHighlightKey.self] }
        set { self[UndoHighlightKey.self] = newValue }
    }
}

@main
struct PDFChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.pdfChatViewModel) private var chatVM: ChatViewModel?
    @FocusedValue(\.pdfChatOpenPicker) private var openPicker: (() -> Void)?
    @FocusedValue(\.pdfChatUndoHighlight) private var undoHighlight: (() -> Void)?

    var body: some Scene {
        // 文档驱动的多窗口场景：Finder 双击 PDF / 拖入 / 应用内打开
        // 都会通过 SwiftUI 的文档架构为每个 PDF 创建独立窗口。
        DocumentGroup(viewing: PDFFileDocument.self) { file in
            ContentView(pdfDoc: file.$document.pdfDocument, fileURL: file.fileURL)
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

        CommandGroup(replacing: .undoRedo) {
            Button("撤销高亮") { undoHighlight?() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(undoHighlight == nil)
        }
    }
}

/// 拦截 ⌘Q 退出：逐个询问有未保存高亮更改的窗口（保存 / 不保存 / 取消），
/// 任一窗口选择「取消」则中止退出；保存失败也中止退出。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 退出路径不经过 windowShouldClose，这里统一清除 NSDocument 编辑标记，
        // 避免系统对 viewing-only 文档尝试 autosave 失败而弹「不支持该操作」。
        DocumentEditStateCleaner.clearAll()
        let dirty = sender.windows.compactMap { ($0.delegate as? WindowCloseDelegate)?.store }
            .filter { $0.hasUnsavedChanges }
        if dirty.isEmpty { return .terminateNow }
        // 在主线程逐个询问；处理完后统一回复。
        Task { @MainActor [weak self] in
            self?.processDirtyStores(dirty) { proceed in
                NSApp.reply(toApplicationShouldTerminate: proceed)
            }
        }
        return .terminateLater
    }

    @MainActor
    private func processDirtyStores(_ stores: [PDFContextStore], completion: @escaping (Bool) -> Void) {
        var index = 0
        func next() {
            if index >= stores.count {
                completion(true)
                return
            }
            let store = stores[index]
            index += 1
            ask(store: store) { action in
                switch action {
                case .cancel:
                    completion(false)
                case .discard:
                    next()
                case .save:
                    let ok = HighlightService.save(document: store.document, to: store.pdfURL)
                    if ok {
                        store.hasUnsavedChanges = false
                        next()
                    } else {
                        self.alertSaveFailure { retry in
                            if retry { index -= 1; next() }
                            else { completion(false) }
                        }
                    }
                }
            }
        }
        next()
    }

    private enum CloseAction { case save, discard, cancel }

    @MainActor
    private func ask(store: PDFContextStore, completion: @escaping (CloseAction) -> Void) {
        let alert = NSAlert()
        alert.messageText = "是否保存对该 PDF 的高亮更改？"
        alert.informativeText = "如果不保存，你最近的高亮更改将被丢弃。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: completion(.save)
        case .alertSecondButtonReturn: completion(.discard)
        default: completion(.cancel)
        }
    }

    @MainActor
    private func alertSaveFailure(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "保存失败"
        alert.informativeText = "无法写入该 PDF 文件，可能没有写入权限。是否重试？"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "重试")
        alert.addButton(withTitle: "取消退出")
        completion(alert.runModal() == .alertFirstButtonReturn)
    }
}