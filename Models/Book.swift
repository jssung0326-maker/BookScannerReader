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
    /// 사용자가 표시한 페이지 북마크. 0부터 시작하는 페이지 인덱스입니다.
    var bookmarkedPageIndices: [Int]

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        pageCount: Int = 0,
        currentPageIndex: Int = 0,
        pdfRelativePath: String? = nil,
        scanProfile: ScanProfile? = nil,
        bookmarkedPageIndices: [Int] = []
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
        self.bookmarkedPageIndices = bookmarkedPageIndices
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case createdAt
        case updatedAt
        case pageCount
        case currentPageIndex
        case pdfRelativePath
        case scanProfile
        case bookmarkedPageIndices
    }

    /// v0.5 이하에서 저장한 서재 데이터에도 북마크 기본값을 넣어 그대로 열 수 있도록 합니다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 0
        currentPageIndex = try container.decodeIfPresent(Int.self, forKey: .currentPageIndex) ?? 0
        pdfRelativePath = try container.decodeIfPresent(String.self, forKey: .pdfRelativePath)
        scanProfile = try container.decodeIfPresent(ScanProfile.self, forKey: .scanProfile)
        bookmarkedPageIndices = try container.decodeIfPresent([Int].self, forKey: .bookmarkedPageIndices) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(pageCount, forKey: .pageCount)
        try container.encode(currentPageIndex, forKey: .currentPageIndex)
        try container.encodeIfPresent(pdfRelativePath, forKey: .pdfRelativePath)
        try container.encodeIfPresent(scanProfile, forKey: .scanProfile)
        try container.encode(bookmarkedPageIndices.sorted(), forKey: .bookmarkedPageIndices)
    }
}
