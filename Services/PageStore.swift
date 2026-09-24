import Foundation
import UIKit

final class PageStore {
    private let fm = FileManager.default

    func loadPages(bookID: UUID) -> [PageRecord] {
        let url = StoragePaths.pagesManifest(bookID: bookID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PageRecord].self, from: data)) ?? []
    }

    func savePages(_ pages: [PageRecord], bookID: UUID) throws {
        try fm.createDirectory(at: StoragePaths.pageImagesDirectory(bookID: bookID), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(pages)
        try data.write(to: StoragePaths.pagesManifest(bookID: bookID), options: .atomic)
    }

    func saveJPEG(_ image: UIImage, bookID: UUID, index: Int, quality: CGFloat = 0.88) throws -> String {
        try fm.createDirectory(at: StoragePaths.pageImagesDirectory(bookID: bookID), withIntermediateDirectories: true)
        let filename = String(format: "%05d.jpg", index + 1)
        let url = StoragePaths.pageImagesDirectory(bookID: bookID).appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "JPEG 변환 실패"])
        }
        try data.write(to: url, options: .atomic)
        return "pages/\(filename)"
    }

    func image(bookID: UUID, relativePath: String) -> UIImage? {
        let url = StoragePaths.bookDirectory(bookID: bookID).appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: url.path)
    }
}
