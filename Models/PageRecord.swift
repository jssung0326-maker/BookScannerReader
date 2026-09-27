import Foundation

struct OCRBlock: Codable, Hashable {
    var text: String
    /// Vision 좌표계(좌하단 원점)의 정규화된 bounding box 입니다.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct PageRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var index: Int
    var imageRelativePath: String
    var ocrText: String
    var ocrBlocks: [OCRBlock]

    init(
        id: UUID = UUID(),
        index: Int,
        imageRelativePath: String,
        ocrText: String = "",
        ocrBlocks: [OCRBlock] = []
    ) {
        self.id = id
        self.index = index
        self.imageRelativePath = imageRelativePath
        self.ocrText = ocrText
        self.ocrBlocks = ocrBlocks
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case index
        case imageRelativePath
        case ocrText
        case ocrBlocks
    }

    /// v0.5 이하 페이지 데이터에도 OCR 블록 기본값을 넣어 그대로 열 수 있도록 합니다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        imageRelativePath = try container.decode(String.self, forKey: .imageRelativePath)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText) ?? ""
        ocrBlocks = try container.decodeIfPresent([OCRBlock].self, forKey: .ocrBlocks) ?? []
    }
}
