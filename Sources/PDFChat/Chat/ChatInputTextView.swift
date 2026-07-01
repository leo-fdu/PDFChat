import SwiftUI
import AppKit

/// 多行输入框：Enter 发送、Shift+Enter 换行，并支持粘贴/拖拽图片。
struct ChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void
    var onPasteImage: (NSImage) -> Void
    var onTextChange: () -> Void

    func makeNSView(context: Context) -> SendableTextView {
        let tv = SendableTextView()
        tv.font = .systemFont(ofSize: 13)
        tv.textColor = .labelColor
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.minSize = NSSize(width: 0, height: 64)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator
        tv.onSend = onSend
        tv.onPasteImage = onPasteImage
        return tv
    }

    func updateNSView(_ nsView: SendableTextView, context: Context) {
        if nsView.string != text { nsView.string = text }
        nsView.onSend = onSend
        nsView.onPasteImage = onPasteImage
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