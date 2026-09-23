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
        // macOS 27 重构了 NSTextView 内部机制：输入法组字期间对文本的任何外部
        // 改写都会重置输入法会话（候选窗只剩最后一个按键、无法上屏），组字中绝不回写
        if tv.string != text && !tv.hasMarkedText() {
            tv.string = text
        }
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
            // 组字期间不同步到 SwiftUI 状态：避免每个按键触发重渲染，
            // 进而避免 updateNSView 在组字中触碰文本；上屏后一次性同步
            guard !tv.hasMarkedText() else { return }
            parent.text = tv.string
            parent.onTextChange()
        }
    }
}

/// 自定义 NSTextView：拦截 Return 与 Cmd+V 粘贴图片。
final class SendableTextView: NSTextView {
    var onSend: () -> Void = {}
    var onPasteImage: (NSImage) -> Void = { _ in }

    // 不重写 keyDown：Enter 在文本系统内部（doCommandBy）拦截，位于输入法之后，
    // 组字中按 Return 会先交给输入法上屏，天然不会触发发送。
    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) {
            if NSEvent.modifierFlags.contains(.shift) {
                super.doCommand(by: selector) // 换行
            } else {
                onSend()
            }
            return
        }
        super.doCommand(by: selector)
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