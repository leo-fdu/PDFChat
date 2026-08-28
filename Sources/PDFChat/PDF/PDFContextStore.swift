import Foundation
import PDFKit
import SwiftUI

enum ContextMode: Equatable {
    case fullDocument
    case selection(String)
}

/// 管理 PDF 文档及其上下文（全文 / 选区），并提供 token 估算。
@MainActor
final class PDFContextStore: ObservableObject {
    @Published var pdfURL: URL?
    @Published private(set) var document: PDFDocument?

    @Published var selectedText: String = ""
    @Published var contextMode: ContextMode = .fullDocument
    /// 是否有未保存到磁盘的高亮更改（高亮 / 撤销后置 true，写盘成功后置 false）。
    @Published var hasUnsavedChanges: Bool = false {
        didSet {
            // 标记为脏的同时清除底层 NSDocument 的编辑标记：
            // 该文档 viewing-only 不支持 autosave，否则系统会尝试自动保存并失败弹窗。
            if hasUnsavedChanges {
                DocumentEditStateCleaner.clear(window: nil, url: pdfURL)
            }
        }
    }

    private var fullTextCache: String = ""

    var fullText: String {
        if fullTextCache.isEmpty { fullTextCache = document?.string ?? "" }
        return fullTextCache
    }

    var contextText: String {
        switch contextMode {
        case .fullDocument: return fullText
        case .selection(let s): return s
        }
    }

    var contextTokenCount: Int {
        TokenEstimator.estimate(contextText)
    }

    var hasSelection: Bool {
        if case .selection = contextMode { return true }
        return false
    }

    var contextLabel: String {
        switch contextMode {
        case .fullDocument: return "全文"
        case .selection(let s):
            let preview = s.prefix(60).replacingOccurrences(of: "\n", with: " ")
            return "选区：\(preview)…"
        }
    }

    func load(url: URL) {
        let resolving = url.resolvingSymlinksInPath()
        if let doc = PDFDocument(url: resolving) {
            self.pdfURL = resolving
            self.document = doc
            self.fullTextCache = ""
            self.selectedText = ""
            self.contextMode = .fullDocument
            self.hasUnsavedChanges = false
        }
    }

    func load(document: PDFDocument, url: URL? = nil) {
        self.pdfURL = url
        self.document = document
        self.fullTextCache = ""
        self.selectedText = ""
        self.contextMode = .fullDocument
        self.hasUnsavedChanges = false
    }

    func updateSelection(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedText = trimmed
        if trimmed.isEmpty {
            if case .selection = contextMode {
                contextMode = .fullDocument
            }
        } else {
            contextMode = .selection(trimmed)
        }
    }

    func resetToFull() {
        contextMode = .fullDocument
    }
}