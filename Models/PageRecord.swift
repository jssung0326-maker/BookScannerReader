import Foundation

struct PageRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var index: Int
    var imageRelativePath: String
    var ocrText: String

    init(id: UUID = UUID(), index: Int, imageRelativePath: String, ocrText: String = "") {
        self.id = id
        self.index = index
        self.imageRelativePath = imageRelativePath
        self.ocrText = ocrText
    }
}
