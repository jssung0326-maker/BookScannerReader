import Foundation
import PDFKit
import UIKit
import CoreText

final class PDFService {
    struct SearchablePage {
        let image: UIImage
        let text: String
    }

    func makePDF(images: [UIImage], destination: URL) throws {
        let pages = images.map { SearchablePage(image: $0, text: "") }
        try makeSearchablePDF(pages: pages, destination: destination)
    }

    /// 이미지 위에 OCR 텍스트를 보이지 않는 PDF 텍스트 객체로 함께 기록합니다.
    /// v0.5에서는 검색/복사를 우선하며, 텍스트 선택 위치를 원문과 완벽히 일치시키는 정밀 좌표 매핑은 후속 버전에서 고도화합니다.
    func makeSearchablePDF(pages: [SearchablePage], destination: URL) throws {
        guard !pages.isEmpty else {
            throw NSError(domain: "PDFService", code: 2, userInfo: [NSLocalizedDescriptionKey: "PDF로 만들 페이지가 없습니다."])
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let firstSize = pages[0].image.size
        let pageWidth: CGFloat = 612
        let firstAspect = firstSize.width > 0 ? firstSize.height / firstSize.width : 1.414
        let pageHeight = max(200, pageWidth * firstAspect)
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        do {
            try renderer.writePDF(to: destination) { context in
                for page in pages {
                    context.beginPage()
                    drawAspectFit(page.image, in: bounds)
                    drawInvisibleOCRText(page.text, in: bounds, context: context.cgContext)
                }
            }
        } catch {
            throw NSError(
                domain: "PDFService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PDF 저장 실패: \(error.localizedDescription)"]
            )
        }
    }

    func copyImportedPDF(from source: URL, bookID: UUID) throws -> URL {
        let fm = FileManager.default
        let bookDir = StoragePaths.bookDirectory(bookID: bookID)
        try fm.createDirectory(at: bookDir, withIntermediateDirectories: true)
        let destination = StoragePaths.pdfURL(bookID: bookID)

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
        return destination
    }

    private func drawAspectFit(_ image: UIImage, in bounds: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: rect)
    }

    private func drawInvisibleOCRText(_ text: String, in bounds: CGRect, context: CGContext) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8)
        ]
        let attributed = NSAttributedString(string: cleaned, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)

        context.saveGState()
        context.setTextDrawingMode(.invisible)

        // CoreText 좌표계를 PDF 좌표계에 맞춥니다.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let textRect = bounds.insetBy(dx: 18, dy: 18)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
