import SwiftUI
import AppKit

/// 多行输入框：Enter 发送、Shift+Enter 换行，并支持粘贴/拖拽图片。
/// 由 NSScrollView 承载并铺满整个输入矩形：点击、滚动、文字边界即整个矩形，
/// 无背景、无边框、无聚焦环，面板内不存在任何内层视图。
struct ChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    var topInset: CGFloat = 12
    var onSend: () -> Void
    var onPasteImage: (NSImage) -> Void
    var onTextChange: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let tv = SendableTextView()
        tv.font = .systemFont(ofSize: 13)
        tv.textColor = .labelColor
        // 背景透明 + 无聚焦环：不绘制任何自身的矩形
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.focusRingType = .none
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        // 加大内边距：光标起始位置离边缘更远；顶部由 topInset 动态控制
        tv.textContainerInset = NSSize(width: 8, height: topInset)
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.delegate = context.coordinator
        tv.onSend = onSend
        tv.onPasteImage = onPasteImage

        // 滚动容器：文字超过面板高度时在矩形内部滚动，而不是溢出裁剪
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? SendableTextView else { return }
        if tv.string != text { tv.string = text }
        // 顶部内边距随悬浮图片行的有无动态变化
        if tv.textContainerInset.height != topInset {
            tv.textContainerInset.height = topInset
        }
        tv.onSend = onSend
        tv.onPasteImage = onPasteImage
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ChatInputTextView
        init(_ parent: ChatInputTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onTextChange()
        }
    }
}

/// 自定义 NSTextView：拦截 Return 与 Cmd+V 粘贴图片。
final class SendableTextView: NSTextView {
    var onSend: () -> Void = {}
    var onPasteImage: (NSImage) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            // 输入法组字中（如中文输入法下临时输入英文）：
            // 回车应先上屏候选文字，而不是直接发送。
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event) // 换行
            } else {
                onSend()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "v" {
            if let img = ImageCoding.imageFromPasteboard() {
                onPasteImage(img)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}