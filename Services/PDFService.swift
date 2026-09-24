import Foundation
import PDFKit
import UIKit

final class PDFService {
    func makePDF(images: [UIImage], destination: URL) throws {
        let document = PDFDocument()

        for (index, image) in images.enumerated() {
            guard let page = PDFPage(image: image) else { continue }
            document.insert(page, at: index)
        }

        guard document.write(to: destination) else {
            throw NSError(domain: "PDFService", code: 1, userInfo: [NSLocalizedDescriptionKey: "PDF 저장 실패"])
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
}
