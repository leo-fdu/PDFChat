import SwiftUI
import UniformTypeIdentifiers

@main
struct PDFChatApp: App {
    @StateObject private var contextStore = PDFContextStore()
    @StateObject private var chatViewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup("PDFChat") {
            ContentView()
                .environmentObject(contextStore)
                .environmentObject(chatViewModel)
                .onOpenURL { url in
                    if url.pathExtension.lowercased() == "pdf" {
                        contextStore.load(url: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openPDFFromMenu)) { _ in
                    NotificationCenter.default.post(name: .openFilePicker, object: nil)
                }
        }
        .commands {
            // 覆盖 New：⌘N 新对话
            CommandGroup(replacing: .newItem) {
                Button("新对话") { chatViewModel.newConversation() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("打开 PDF…") {
                    NotificationCenter.default.post(name: .openPDFFromMenu, object: nil)
                }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let openPDFFromMenu = Notification.Name("openPDFFromMenu")
    static let openFilePicker = Notification.Name("openFilePicker")
}

enum AppActions {
    static func openSettings() {
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}