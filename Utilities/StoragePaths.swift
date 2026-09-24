import Foundation

struct StoragePaths {
    static let documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let booksDirectory = documentsDirectory.appendingPathComponent("Books", isDirectory: true)
    static let libraryFile = documentsDirectory.appendingPathComponent("Library.json")

    static func bookDirectory(bookID: UUID) -> URL {
        booksDirectory.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    static func pageImagesDirectory(bookID: UUID) -> URL {
        bookDirectory(bookID: bookID).appendingPathComponent("pages", isDirectory: true)
    }

    static func pagesManifest(bookID: UUID) -> URL {
        bookDirectory(bookID: bookID).appendingPathComponent("pages.json")
    }

    static func pdfURL(bookID: UUID) -> URL {
        bookDirectory(bookID: bookID).appendingPathComponent("book.pdf")
    }
}
