import SwiftUI
import PDFKit

struct PDFReaderView: UIViewRepresentable {
    let url: URL
    @Binding var pageIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(pageIndex: $pageIndex)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)

        if let document = PDFDocument(url: url) {
            view.document = document
            let safeIndex = min(max(pageIndex, 0), max(document.pageCount - 1, 0))
            if let page = document.page(at: safeIndex) {
                view.go(to: page)
            }
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let document = uiView.document, document.pageCount > 0 else { return }
        let safeIndex = min(max(pageIndex, 0), document.pageCount - 1)
        if let current = uiView.currentPage,
           document.index(for: current) == safeIndex {
            return
        }
        if let page = document.page(at: safeIndex) {
            uiView.go(to: page)
        }
    }

    final class Coordinator: NSObject {
        private var pageIndex: Binding<Int>

        init(pageIndex: Binding<Int>) {
            self.pageIndex = pageIndex
        }

        @objc func pageChanged(_ notification: Notification) {
            guard
                let view = notification.object as? PDFView,
                let document = view.document,
                let current = view.currentPage
            else { return }

            let index = document.index(for: current)
            if pageIndex.wrappedValue != index {
                pageIndex.wrappedValue = index
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
