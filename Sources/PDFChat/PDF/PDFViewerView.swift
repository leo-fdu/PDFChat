import SwiftUI
import PDFKit
import AppKit

struct PDFViewerView: NSViewRepresentable {
    @ObservedObject var store: PDFContextStore

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displaysPageBreaks = true
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor
        context.coordinator.pdfView = pdfView

        // 监听选区变化
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = store.document
    }

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        let store: PDFContextStore
        init(store: PDFContextStore) { self.store = store }

        @objc func selectionChanged(_ note: Notification) {
            guard let pv = pdfView else { return }
            let sel = pv.currentSelection
            let text = sel?.string ?? ""
            Task { @MainActor in store.updateSelection(text) }
        }
    }
}