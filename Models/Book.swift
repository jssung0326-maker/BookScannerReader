import Foundation

struct Book: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var author: String
    var createdAt: Date
    var updatedAt: Date
    var pageCount: Int
    var currentPageIndex: Int
    var pdfRelativePath: String?
    var scanProfile: ScanProfile?

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        pageCount: Int = 0,
        currentPageIndex: Int = 0,
        pdfRelativePath: String? = nil,
        scanProfile: ScanProfile? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pageCount = pageCount
        self.currentPageIndex = currentPageIndex
        self.pdfRelativePath = pdfRelativePath
        self.scanProfile = scanProfile
    }
}
