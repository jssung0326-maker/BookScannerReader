import Foundation
import UIKit

final class PageStore {
    private let fm = FileManager.default

    func loadPages(bookID: UUID) -> [PageRecord] {
        let url = StoragePaths.pagesManifest(bookID: bookID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let pages = (try? JSONDecoder().decode([PageRecord].self, from: data)) ?? []
        return pages.sorted { $0.index < $1.index }
    }

    func savePages(_ pages: [PageRecord], bookID: UUID) throws {
        try fm.createDirectory(at: StoragePaths.pageImagesDirectory(bookID: bookID), withIntermediateDirectories: true)
        let normalized = pages.enumerated().map { offset, page -> PageRecord in
            var copy = page
            copy.index = offset
            return copy
        }
        let data = try JSONEncoder().encode(normalized)
        try data.write(to: StoragePaths.pagesManifest(bookID: bookID), options: .atomic)
    }

    func saveJPEG(_ image: UIImage, bookID: UUID, index: Int, quality: CGFloat = 0.88) throws -> String {
        try fm.createDirectory(at: StoragePaths.pageImagesDirectory(bookID: bookID), withIntermediateDirectories: true)
        let filename = String(format: "%05d.jpg", index + 1)
        let url = StoragePaths.pageImagesDirectory(bookID: bookID).appendingPathComponent(filename)
        try writeJPEG(image, to: url, quality: quality)
        return "pages/\(filename)"
    }

    func overwriteJPEG(_ image: UIImage, bookID: UUID, relativePath: String, quality: CGFloat = 0.88) throws {
        let url = StoragePaths.bookDirectory(bookID: bookID).appendingPathComponent(relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJPEG(image, to: url, quality: quality)
    }

    func deleteImage(bookID: UUID, relativePath: String) throws {
        let url = StoragePaths.bookDirectory(bookID: bookID).appendingPathComponent(relativePath)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    func image(bookID: UUID, relativePath: String) -> UIImage? {
        let url = StoragePaths.bookDirectory(bookID: bookID).appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: url.path)
    }

    func images(bookID: UUID, pages: [PageRecord]) -> [UIImage] {
        pages.compactMap { image(bookID: bookID, relativePath: $0.imageRelativePath) }
    }

    private func writeJPEG(_ image: UIImage, to url: URL, quality: CGFloat) throws {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "JPEG 변환 실패"])
        }
        try data.write(to: url, options: .atomic)
    }
}
