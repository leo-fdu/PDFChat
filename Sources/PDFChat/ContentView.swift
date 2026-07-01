import SwiftUI

struct ContentView: View {
    @EnvironmentObject var contextStore: PDFContextStore
    @EnvironmentObject var chatViewModel: ChatViewModel
    @State private var sidebarVisible: Bool = true
    @State private var showOpenSheet = false

    var body: some View {
        HSplitView {
            pdfPane
                .frame(minWidth: 360)
            if sidebarVisible {
                ChatSidebarView(viewModel: chatViewModel, contextStore: contextStore)
                    .frame(maxWidth: 480)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showOpenSheet = true
                } label: {
                    Label("打开 PDF", systemImage: "folder")
                }
                Button {
                    withAnimation { sidebarVisible.toggle() }
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
                if let u = urls.first { contextStore.load(url: u) }
            case .failure: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFilePicker)) { _ in
            showOpenSheet = true
        }
    }

    private var pdfPane: some View {
        Group {
            if contextStore.document != nil {
                PDFViewerView(store: contextStore)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("双击 PDF 文件或点击「打开 PDF」")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}