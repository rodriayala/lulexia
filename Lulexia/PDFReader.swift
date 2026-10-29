import SwiftUI
import PDFKit

struct PDFReader: UIViewRepresentable {
    @ObservedObject var model: ReaderModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeUIView(context: Context) -> PDFView {
        let view = ZoomablePDFView()
        view.clipsToBounds = true
        view.autoScales = false
        view.minScaleFactor = 0.05
        view.maxScaleFactor = 8
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PDFView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
    func updateUIView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        if view.document !== model.document {
            view.document = model.document
            coordinator.lastSentence = nil
            (view as? ZoomablePDFView)?.resetWidthFit()
            coordinator.lastZoom = model.zoomRequest?.id
        }
        if let request = model.zoomRequest, coordinator.lastZoom != request.id {
            coordinator.lastZoom = request.id
            (view as? ZoomablePDFView)?.apply(request.action)
        }
        if let jump = model.chapterJump, coordinator.lastJump != jump.id {
            coordinator.lastJump = jump.id
            coordinator.lastSentence = model.sentence?.id
            view.go(to: jump.destination)
        }
        guard let sentence = model.sentence, let page = model.document?.page(at: sentence.page) else { view.highlightedSelections = []; view.clearSelection(); return }
        var selections: [PDFSelection] = []
        if model.highlight, let selection = page.selection(for: sentence.range) {
            selection.color = UIColor.systemYellow.withAlphaComponent(0.35)
            selections.append(selection)
        }
        if model.magnify, let range = model.wordRange, let selection = page.selection(for: range) {
            selection.color = UIColor.systemTeal.withAlphaComponent(0.45)
            selections.append(selection)
        }
        view.highlightedSelections = selections
        if coordinator.lastSentence != sentence.id {
            coordinator.lastSentence = sentence.id
            if let selection = page.selection(for: sentence.range) { view.go(to: selection) }
        }
    }
    @MainActor final class Coordinator: NSObject {
        let model: ReaderModel
        var lastSentence: Int?
        var lastJump: UUID?
        var lastZoom: UUID?
        init(_ model: ReaderModel) { self.model = model }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PDFView else { return }
            let point = gesture.location(in: view)
            guard let page = view.page(for: point, nearest: false) else { return }
            let local = view.convert(point, to: page)
            let character = page.characterIndex(at: local)
            guard character != NSNotFound, character >= 0,
                  page.characterBounds(at: character).insetBy(dx: -4, dy: -4).contains(local),
                  let pageNumber = model.document?.index(for: page),
                  let index = model.sentences.firstIndex(where: { $0.page == pageNumber && NSLocationInRange(character, $0.range) }) else { return }
            model.select(index)
        }
    }
}

@MainActor
final class ZoomablePDFView: PDFView {
    private var fitsWidth = true
    private var fittedWidth: CGFloat = 0

    func resetWidthFit() {
        fitsWidth = true
        fittedWidth = 0
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if fitsWidth && bounds.width > 0 && abs(bounds.width - fittedWidth) > 0.5 {
            fittedWidth = bounds.width
            fitWidth()
        }
    }
    private func fitWidth() {
        guard let page = currentPage ?? document?.page(at: 0) else { return }
        let box = page.bounds(for: displayBox)
        let rotated = abs(page.rotation % 180) == 90
        let width = rotated ? box.height : box.width
        guard width > 0, bounds.width > 16 else { return }
        changeScale(to: (bounds.width - 16) / width)
    }
    func apply(_ action: DocumentZoomAction) {
        switch action {
        case .fitWidth:
            fitsWidth = true
            fittedWidth = bounds.width
            fitWidth()
        case .closer:
            fitsWidth = false
            changeScale(to: scaleFactor * 1.2)
        case .farther:
            fitsWidth = false
            changeScale(to: scaleFactor / 1.2)
        }
    }
    private func changeScale(to requested: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let page = self.page(for: center, nearest: true)
        let anchor = page.map { convert(center, to: $0) }
        scaleFactor = min(maxScaleFactor, max(minScaleFactor, requested))
        layoutIfNeeded()
        if let page, let anchor {
            let size = CGSize(width: bounds.width / scaleFactor, height: bounds.height / scaleFactor)
            go(to: CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2,
                          width: size.width, height: size.height), on: page)
        }
    }
}
