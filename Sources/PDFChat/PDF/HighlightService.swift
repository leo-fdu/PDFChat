import Foundation
import PDFKit
import AppKit

/// 高亮操作记录，用于撤销栈。
enum HighlightOp {
    case add([PDFAnnotation])
    case remove(PDFAnnotation, PDFPage)
}

/// 负责向 PDF 添加 / 移除高亮注解并写回原文件。
enum HighlightService {
    /// 纯荧光黄 (#FFFF00)，高 alpha 保证白底上饱和鲜艳。
    static let highlightColor = NSColor(srgbRed: 1.0, green: 1.0, blue: 0.0, alpha: 0.9)

    /// 为给定选区添加高亮。用 selectionsByLine 按行拆分，每行一条注解，
    /// bounds 紧贴该行文字，避免整行被撑满。
    /// 返回实际创建的注解列表（每行一条）。
    @discardableResult
    static func addHighlight(for selection: PDFSelection?) -> [PDFAnnotation] {
        guard let selection else { return [] }
        let lines = selection.selectionsByLine()
        guard !lines.isEmpty else { return [] }
        var added: [PDFAnnotation] = []
        for line in lines {
            guard let page = line.pages.first else { continue }
            let rect = line.bounds(for: page)
            guard rect.width > 0, rect.height > 0 else { continue }
            let ann = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            ann.color = highlightColor
            page.addAnnotation(ann)
            added.append(ann)
        }
        return added
    }

    /// 撤销一次高亮操作。
    static func undo(_ op: HighlightOp) {
        switch op {
        case .add(let anns):
            for ann in anns {
                if let page = ann.page { page.removeAnnotation(ann) }
            }
        case .remove(let ann, let page):
            page.addAnnotation(ann)
        }
    }

    /// 将文档（含当前高亮）写回 url；失败返回 false。
    @discardableResult
    static func save(document: PDFDocument?, to url: URL?) -> Bool {
        guard let document, let url else { return false }
        return document.write(to: url)
    }
}