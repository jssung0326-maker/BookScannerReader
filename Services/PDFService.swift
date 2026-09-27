import Foundation
import PDFKit
import UIKit
import CoreText

final class PDFService {
    struct SearchablePage {
        let image: UIImage
        let text: String
        let blocks: [OCRBlock]

        init(image: UIImage, text: String, blocks: [OCRBlock] = []) {
            self.image = image
            self.text = text
            self.blocks = blocks
        }
    }

    func makePDF(images: [UIImage], destination: URL) throws {
        let pages = images.map { SearchablePage(image: $0, text: "") }
        try makeSearchablePDF(pages: pages, destination: destination)
    }

    /// 스캔 이미지를 PDF로 만들고 OCR 텍스트를 보이지 않는 텍스트 레이어로 함께 기록합니다.
    /// OCR bounding box가 있으면 각 문장 위치에 맞춰 기록하고, 구버전 데이터는 전체 텍스트 방식으로 대체합니다.
    func makeSearchablePDF(
        pages: [SearchablePage],
        destination: URL,
        title: String? = nil,
        author: String? = nil
    ) throws {
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

        let format = UIGraphicsPDFRendererFormat()
        var info: [String: Any] = [:]
        if let title, !title.isEmpty { info[kCGPDFContextTitle as String] = title }
        if let author, !author.isEmpty { info[kCGPDFContextAuthor as String] = author }
        if !info.isEmpty { format.documentInfo = info }

        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        do {
            try renderer.writePDF(to: destination) { context in
                for page in pages {
                    context.beginPage()
                    let imageRect = aspectFitRect(for: page.image, in: bounds)
                    page.image.draw(in: imageRect)

                    if page.blocks.isEmpty {
                        drawInvisibleOCRText(page.text, in: bounds, context: context.cgContext)
                    } else {
                        drawInvisibleOCRBlocks(page.blocks, imageRect: imageRect, pageBounds: bounds, context: context.cgContext)
                    }
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

    func documentInfo(at url: URL) -> (title: String?, author: String?, pageCount: Int) {
        guard let document = PDFDocument(url: url) else { return (nil, nil, 0) }
        let attributes = document.documentAttributes ?? [:]
        let title = attributes[PDFDocumentAttribute.titleAttribute] as? String
        let author = attributes[PDFDocumentAttribute.authorAttribute] as? String
        return (title, author, document.pageCount)
    }

    private func aspectFitRect(for image: UIImage, in bounds: CGRect) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else { return bounds }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func drawInvisibleOCRBlocks(
        _ blocks: [OCRBlock],
        imageRect: CGRect,
        pageBounds: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)

        // CoreText가 사용할 수 있도록 좌표계를 y-up으로 되돌립니다.
        context.translateBy(x: 0, y: pageBounds.height)
        context.scaleBy(x: 1, y: -1)

        for block in blocks where !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let x = imageRect.minX + CGFloat(block.x) * imageRect.width
            let topY = imageRect.minY + (1 - CGFloat(block.y) - CGFloat(block.height)) * imageRect.height
            let width = max(4, CGFloat(block.width) * imageRect.width)
            let height = max(5, CGFloat(block.height) * imageRect.height)
            let rect = CGRect(x: x, y: topY, width: width, height: height)

            let fontSize = min(max(height * 0.72, 4), 18)
            let attributed = NSAttributedString(
                string: block.text,
                attributes: [.font: UIFont.systemFont(ofSize: fontSize)]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
            let path = CGPath(rect: rect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, context)
        }

        context.restoreGState()
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
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let textRect = bounds.insetBy(dx: 18, dy: 18)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
