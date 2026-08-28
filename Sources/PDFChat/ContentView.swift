import SwiftUI
import PDFKit

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var contextStore = PDFContextStore()
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var historyStore = ConversationHistoryStore()
    @State private var sidebarVisible: Bool = true
    @State private var showOpenSheet = false
    @State private var undoHighlight: (() -> Void)?

    let pdfDocBinding: Binding<PDFDocument?>
    let fileURL: URL?

    init(pdfDoc: Binding<PDFDocument?>, fileURL: URL? = nil) {
        self.pdfDocBinding = pdfDoc
        self.fileURL = fileURL
    }

    var body: some View {
        HSplitView {
            pdfPane
                .focusable()
                .frame(minWidth: 360)
            if sidebarVisible {
                ChatSidebarView(viewModel: chatViewModel, contextStore: contextStore, historyStore: historyStore)
                    .frame(maxWidth: 480)
            }
        }
        .onAppear {
            chatViewModel.history = historyStore
            loadIfNeeded()
        }
        .onChange(of: pdfDocBinding.wrappedValue) { _, _ in loadIfNeeded() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showOpenSheet = true
                } label: {
                    Label("打开 PDF", systemImage: "folder")
                }
                Button {
                    // 不做动画：HSplitView 动画会带动大量 WKWebView 重排版，明显掉帧
                    sidebarVisible.toggle()
                } label: {
                    Label("侧边栏", systemImage: "sidebar.trailing")
                }
                Button {
                    chatViewModel.newConversation()
                } label: {
                    Label("新对话", systemImage: "plus.bubble")
                }
                .help("新对话 (⌘N)")
            }
        }
        .fileImporter(isPresented: $showOpenSheet,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let u = urls.first {
                    // 通过系统文档控制器在新窗口打开该文件
                    NSDocumentController.shared.openDocument(withContentsOf: u, display: true) { _, _, _ in }
                }
            case .failure: break
            }
        }
        .focusedSceneValue(\.pdfChatViewModel, chatViewModel)
        .focusedSceneValue(\.pdfChatOpenPicker) { showOpenSheet = true }
        .focusedSceneValue(\.pdfChatUndoHighlight, undoHighlight)
    }

    private func loadIfNeeded() {
        guard let doc = pdfDocBinding.wrappedValue, contextStore.document == nil else { return }
        contextStore.load(document: doc, url: fileURL)
        chatViewModel.history = historyStore
        // 加载该 PDF 的历史对话，并自动恢复最近一条
        historyStore.load(for: contextStore.pdfURL ?? fileURL)
        if let latest = historyStore.conversations.first {
            chatViewModel.restore(messages: historyStore.load(latest))
        }
    }

    private var pdfPane: some View {
        Group {
            if contextStore.document != nil {
                PDFViewerView(store: contextStore, undoHandler: $undoHighlight)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("双击 PDF 文件或点击「打开 PDF」")
                        .foregroundColor(.secondary)
                    Text("⌘N 新对话；双击 Finder 中的 PDF 可在新窗口打开")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}