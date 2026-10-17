import SwiftUI

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
    @NSApplicationDelegateAdaptor(ReaderAppDelegate.self) private var appDelegate
    @FocusedValue(\.pdfChatViewModel) private var chatVM
    @FocusedValue(\.pdfChatOpenPicker) private var openPicker
    var body: some Scene {
        DocumentGroup(viewing: PDFFileDocument.self) { file in
            ContentView(pdfDoc: file.$document.pdfDocument, fileURL: file.fileURL)
                .tint(Color(red: 0.34, green: 0.39, blue: 0.82))
        }
        .defaultSize(width: 1220, height: 820)
        .commands { commands }
        WindowGroup("PDFChat") {
            ContentView(pdfDoc: .constant(nil)).tint(Color(red: 0.34, green: 0.39, blue: 0.82))
        }.defaultSize(width: 1220, height: 820)
        Settings { SettingsView() }
    }
    @CommandsBuilder private var commands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New chat") { chatVM?.newConversation() }.keyboardShortcut("n", modifiers: .command).disabled(chatVM == nil)
            Button("Open PDF…") { openPicker?() }.keyboardShortcut("o", modifiers: .command)
        }
    }
}

@MainActor final class ReaderAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for model in ChatViewModel.liveModels.allObjects { model.stop() }
        Task {
            await HistoryDiskWriter.shared.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
