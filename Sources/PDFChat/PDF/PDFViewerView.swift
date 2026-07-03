import SwiftUI
import PDFKit
import AppKit
import ObjectiveC

// MARK: - Swizzle PDFView.menu(for:) 彻底禁用右键菜单
// PDFKit 注解右键菜单（Add Note / Remove Highlight / Change Color）走内部路径，
// willOpenMenu / rightMouseDown / event monitor 都拦不住。唯一可靠方案：
// 运行时替换 PDFView 的 menu(for:) 实现，直接返回 nil，让所有右键无任何菜单。
private let swizzlePDFViewMenu: Void = {
    let cls = PDFView.self
    let original = class_getInstanceMethod(cls, #selector(NSView.menu(for:)))
    let blocked: @convention(block) (AnyObject, NSEvent) -> NSMenu? = { _, _ in nil }
    let blockedIMP = imp_implementationWithBlock(blocked)
    if let original {
        method_setImplementation(original, blockedIMP)
    }
}()

/// PDF 视图 + 右下角浮动缩放条，支持触控板双指捏合缩放。
struct PDFViewerView: View {
    @ObservedObject var store: PDFContextStore
    @State private var zoom: CGFloat = 1.0
    @State private var fitScale: CGFloat = 1.0
    /// 由 Representable 写入的撤销闭包，供外层经 FocusedValue 暴露给 ⌘Z 菜单。
    @Binding var undoHandler: (() -> Void)?

    init(store: PDFContextStore, undoHandler: Binding<(() -> Void)?> = .constant(nil)) {
        self.store = store
        self._undoHandler = undoHandler
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PDFViewRepresentable(
                store: store,
                zoom: $zoom,
                fitScale: $fitScale,
                undoHandler: $undoHandler
            )
            zoomBar
                .padding(12)
        }
    }

    private var zoomBar: some View {
        HStack(spacing: 4) {
            Button { setRelativeScale(0.8) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .help("缩小")

            Text("\(Int((zoom * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 48)
                .font(.caption)

            Button { setRelativeScale(1.25) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("放大")

            Divider().frame(height: 14)

            Button { resetToFit() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("适应当前大小")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))
    }

    private func setRelativeScale(_ factor: CGFloat) {
        zoom = min(max(zoom * factor, 0.25), 4.0)
    }

    private func resetToFit() {
        zoom = fitScale > 0 ? fitScale : 1.0
    }
}

/// 自定义 PDFView：原生支持触控板双指捏合，并对外发布缩放变化；
/// 同时承载选区高亮弹窗与撤销栈。
final class ZoomablePDFView: PDFView {
    var onScaleChange: ((CGFloat, CGFloat) -> Void)?
    /// 用户确认高亮：把当前选区转为高亮并标记未保存。
    var onHighlightRequested: (() -> Void)?

    private let highlightPopover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        return p
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _ = swizzlePDFViewMenu
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        _ = swizzlePDFViewMenu
    }

    /// 视图挂到窗口后，安装关闭拦截 delegate。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // 通过 onAttachToWindow 闭包通知 Coordinator 安装 delegate。
        onAttachToWindow?()
    }

    /// 由 Representable 注入：触发 Coordinator.installCloseDelegateIfNeeded。
    var onAttachToWindow: (() -> Void)?

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        // 延迟到下一 runloop 再读取 scaleFactor：捏合期间同步读到的值尚未提交，
        // 会导致 onScaleChange 上报旧值（与 smartMagnify 的处理保持一致）。
        DispatchQueue.main.async { [weak self] in self?.clampAndNotify() }
    }

    override func endGesture(with event: NSEvent) {
        super.endGesture(with: event)
        // 手势结束时再补一次，确保捕获 PDFKit 最终提交的缩放值。
        DispatchQueue.main.async { [weak self] in self?.clampAndNotify() }
    }

    override func smartMagnify(with event: NSEvent) {
        super.smartMagnify(with: event)
        DispatchQueue.main.async { [weak self] in self?.clampAndNotify() }
    }

    private func clampAndNotify() {
        let lo = Swift.max(minScaleFactor, 0.25)
        let hi = Swift.max(maxScaleFactor, lo)
        if scaleFactor < lo { scaleFactor = lo }
        else if scaleFactor > hi { scaleFactor = hi }
        onScaleChange?(scaleFactor, scaleFactorForSizeToFit)
    }

    // MARK: - 选区高亮弹窗

    func showHighlightPopover(for selection: PDFSelection?) {
        guard let sel = selection,
              !(sel.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let page = sel.pages.first else {
            hideHighlightPopover()
            return
        }
        let rectInView = convert(sel.bounds(for: page), from: page)

        let vc = NSViewController()
        let btn = NSButton(title: "高亮", target: self, action: #selector(handleHighlight))
        btn.bezelStyle = .regularSquare
        btn.font = .systemFont(ofSize: 13, weight: .medium)
        btn.contentTintColor = .labelColor
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 28))
        btn.frame = NSRect(x: 6, y: 4, width: 60, height: 20)
        container.addSubview(btn)
        vc.view = container
        highlightPopover.contentViewController = vc
        // 锚点取选区上边中点；若上方空间不足则用下边。
        var anchor = NSRect(x: rectInView.midX - 1, y: rectInView.maxY - 1, width: 2, height: 2)
        if rectInView.maxY + 40 > bounds.maxY {
            anchor.origin.y = rectInView.minY - 1
        }
        highlightPopover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
    }

    func hideHighlightPopover() {
        highlightPopover.close()
    }

    @objc private func handleHighlight() {
        onHighlightRequested?()
        hideHighlightPopover()
    }
}

struct PDFViewRepresentable: NSViewRepresentable {
    @ObservedObject var store: PDFContextStore
    @Binding var zoom: CGFloat
    @Binding var fitScale: CGFloat
    @Binding var undoHandler: (() -> Void)?

    func makeNSView(context: Context) -> ZoomablePDFView {
        let v = ZoomablePDFView()
        v.autoScales = false
        v.displaysPageBreaks = true
        v.displayDirection = .vertical
        v.backgroundColor = .windowBackgroundColor
        v.minScaleFactor = 0.25
        v.maxScaleFactor = 4.0
        v.onScaleChange = { newZoom, newFit in
            zoom = newZoom
            fitScale = newFit
        }
        context.coordinator.store = store
        context.coordinator.pdfView = v
        // 选区高亮弹窗：把当前选区转为高亮，记录撤销栈并标记未保存（不立即写盘）。
        v.onHighlightRequested = { [weak v, weak store] in
            guard let pv = v, let store, store.document != nil else { return }
            let added = HighlightService.addHighlight(for: pv.currentSelection)
            if !added.isEmpty {
                context.coordinator.undoStack.append(.add(added))
                store.hasUnsavedChanges = true
            }
            pv.currentSelection = nil
        }
        // 暴露撤销闭包给外层。
        let coordinator = context.coordinator
        undoHandler = { [weak coordinator] in coordinator?.undoLast() }
        v.onAttachToWindow = { [weak coordinator] in
            Task { @MainActor in coordinator?.installCloseDelegateIfNeeded() }
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: v
        )
        return v
    }

    func updateNSView(_ nsView: ZoomablePDFView, context: Context) {
        context.coordinator.store = store
        if nsView.document !== store.document {
            nsView.document = store.document
            DispatchQueue.main.async {
                let fit = nsView.scaleFactorForSizeToFit
                if fit > 0 {
                    fitScale = fit
                    nsView.scaleFactor = fit
                    zoom = fit
                    context.coordinator.lastAppliedZoom = fit
                }
            }
        } else {
            // 仅当 zoom 被 app 主动改动（按钮 / 重置）时才把缩放推给 view。
            // 这样选中文本等无关重渲染不会用陈旧的 zoom 覆盖 view 的真实缩放，
            // 彻底避免「捏合后选中文本跳回原大小」的问题。
            if context.coordinator.lastAppliedZoom != zoom,
               abs(nsView.scaleFactor - zoom) > 0.001 {
                nsView.scaleFactor = zoom
                context.coordinator.lastAppliedZoom = zoom
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var pdfView: ZoomablePDFView?
        weak var store: PDFContextStore?
        // 记录最后一次由 app 主动推送给 view 的 zoom 值，用于判断 updateNSView
        // 是否需要再次写 scaleFactor（见 PDFViewRepresentable.updateNSView）。
        var lastAppliedZoom: CGFloat?
        /// 高亮操作撤销栈。
        var undoStack: [HighlightOp] = []
        /// 窗口关闭拦截 delegate（强持有，避免释放）。
        var closeDelegate: WindowCloseDelegate?

        @objc func selectionChanged(_ note: Notification) {
            guard let pv = pdfView else { return }
            let sel = pv.currentSelection
            let text = sel?.string ?? ""
            Task { @MainActor in store?.updateSelection(text) }
            pv.showHighlightPopover(for: sel)
        }

        /// 撤销最近一次高亮操作并标记未保存（不立即写盘）。
        @MainActor
        func undoLast() {
            guard let store, let op = undoStack.popLast() else { return }
            HighlightService.undo(op)
            store.hasUnsavedChanges = true
        }

        /// 安装窗口关闭拦截（仅一次）。
        @MainActor
        func installCloseDelegateIfNeeded() {
            guard closeDelegate == nil, let pv = pdfView, let window = pv.window else { return }
            let d = WindowCloseDelegate(store: store)
            // 保留 SwiftUI 原有 delegate 的行为，仅拦截 windowShouldClose。
            d.originalDelegate = window.delegate
            window.delegate = d
            closeDelegate = d
        }
    }
}

/// 拦截窗口关闭：若有未保存的高亮，弹窗询问「保存 / 不保存 / 取消」。
/// 对 windowShouldClose 以外的消息转发给 SwiftUI 原始 delegate，不破坏窗口生命周期。
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var store: PDFContextStore?
    weak var originalDelegate: NSWindowDelegate?

    init(store: PDFContextStore?) {
        self.store = store
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let store, store.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "是否保存对该 PDF 的高亮更改？"
        alert.informativeText = "如果不保存，你最近的高亮更改将被丢弃。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // 保存
            let ok = HighlightService.save(document: store.document, to: store.pdfURL)
            if ok { store.hasUnsavedChanges = false }
            return ok
        case .alertSecondButtonReturn: // 不保存
            return true
        default: // 取消
            return false
        }
    }

    // 把其它 delegate 方法转发给 SwiftUI 原始 delegate。
    override func responds(to aSelector: Selector) -> Bool {
        super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector) -> Any? {
        if let d = originalDelegate, d.responds(to: aSelector) { return d }
        return super.forwardingTarget(for: aSelector)
    }
}