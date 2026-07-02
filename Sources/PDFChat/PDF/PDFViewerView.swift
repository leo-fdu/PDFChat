import SwiftUI
import PDFKit
import AppKit

/// PDF 视图 + 右下角浮动缩放条，支持触控板双指捏合缩放。
struct PDFViewerView: View {
    @ObservedObject var store: PDFContextStore
    @State private var zoom: CGFloat = 1.0
    @State private var fitScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PDFViewRepresentable(
                store: store,
                zoom: $zoom,
                fitScale: $fitScale
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

/// 自定义 PDFView：原生支持触控板双指捏合，并对外发布缩放变化。
final class ZoomablePDFView: PDFView {
    var onScaleChange: ((CGFloat, CGFloat) -> Void)?

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
}

struct PDFViewRepresentable: NSViewRepresentable {
    @ObservedObject var store: PDFContextStore
    @Binding var zoom: CGFloat
    @Binding var fitScale: CGFloat

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

        @objc func selectionChanged(_ note: Notification) {
            guard let pv = pdfView else { return }
            let text = pv.currentSelection?.string ?? ""
            Task { @MainActor in store?.updateSelection(text) }
        }
    }
}