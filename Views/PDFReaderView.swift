import SwiftUI
import PDFKit

struct PDFReaderView: UIViewRepresentable {
    let url: URL
    var initialPageIndex: Int = 0

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)

        if let document = PDFDocument(url: url) {
            view.document = document
            if initialPageIndex >= 0, initialPageIndex < document.pageCount,
               let page = document.page(at: initialPageIndex) {
                view.go(to: page)
            }
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
