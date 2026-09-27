import Foundation

struct ScanProfile: Codable, Hashable {
    enum CaptureMode: String, Codable, CaseIterable, Identifiable {
        case singlePage
        case doublePage

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .singlePage: return "1페이지"
            case .doublePage: return "2페이지"
            }
        }
    }

    enum FitMode: String, Codable, CaseIterable, Identifiable {
        case aspectFit
        case aspectFill

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .aspectFit: return "여백 유지"
            case .aspectFill: return "화면 채우기"
            }
        }
    }

    enum ReadingOrder: String, Codable, CaseIterable, Identifiable {
        case leftToRight
        case rightToLeft

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .leftToRight: return "왼쪽 → 오른쪽"
            case .rightToLeft: return "오른쪽 → 왼쪽"
            }
        }
    }

    var captureMode: CaptureMode
    /// width / height
    var pageAspectRatio: Double
    /// 저장용 기준 폭(px). 높이는 aspect ratio로 계산합니다.
    var outputWidthPixels: Int
    var fitMode: FitMode
    var ocrLanguages: [String]

    /// 두 페이지 촬영 시 첫 번째 기준 분리선. 0.5 = 정확한 중앙.
    var splitPosition: Double
    /// true이면 각 촬영 이미지마다 중앙 제본선 후보를 자동으로 탐색합니다.
    var autoDetectSplit: Bool
    /// 두 페이지 촬영 후 페이지를 저장하는 순서입니다.
    var readingOrder: ReadingOrder

    var outputHeightPixels: Int {
        guard pageAspectRatio > 0 else { return outputWidthPixels }
        return Int((Double(outputWidthPixels) / pageAspectRatio).rounded())
    }

    init(
        captureMode: CaptureMode,
        pageAspectRatio: Double,
        outputWidthPixels: Int,
        fitMode: FitMode,
        ocrLanguages: [String],
        splitPosition: Double = 0.5,
        autoDetectSplit: Bool = true,
        readingOrder: ReadingOrder = .leftToRight
    ) {
        self.captureMode = captureMode
        self.pageAspectRatio = pageAspectRatio
        self.outputWidthPixels = outputWidthPixels
        self.fitMode = fitMode
        self.ocrLanguages = ocrLanguages
        self.splitPosition = min(max(splitPosition, 0.35), 0.65)
        self.autoDetectSplit = autoDetectSplit
        self.readingOrder = readingOrder
    }

    static let initial = ScanProfile(
        captureMode: .doublePage,
        pageAspectRatio: 0.70,
        outputWidthPixels: 1800,
        fitMode: .aspectFit,
        ocrLanguages: ["ko-KR", "en-US"],
        splitPosition: 0.5,
        autoDetectSplit: true,
        readingOrder: .leftToRight
    )

    private enum CodingKeys: String, CodingKey {
        case captureMode
        case pageAspectRatio
        case outputWidthPixels
        case fitMode
        case ocrLanguages
        case splitPosition
        case autoDetectSplit
        case readingOrder
    }

    /// v0.2에서 저장한 ScanProfile에도 새 기본값을 넣어 그대로 열 수 있도록 합니다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureMode = try container.decode(CaptureMode.self, forKey: .captureMode)
        pageAspectRatio = try container.decode(Double.self, forKey: .pageAspectRatio)
        outputWidthPixels = try container.decode(Int.self, forKey: .outputWidthPixels)
        fitMode = try container.decode(FitMode.self, forKey: .fitMode)
        ocrLanguages = try container.decode([String].self, forKey: .ocrLanguages)
        splitPosition = try container.decodeIfPresent(Double.self, forKey: .splitPosition) ?? 0.5
        autoDetectSplit = try container.decodeIfPresent(Bool.self, forKey: .autoDetectSplit) ?? true
        readingOrder = try container.decodeIfPresent(ReadingOrder.self, forKey: .readingOrder) ?? .leftToRight
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(captureMode, forKey: .captureMode)
        try container.encode(pageAspectRatio, forKey: .pageAspectRatio)
        try container.encode(outputWidthPixels, forKey: .outputWidthPixels)
        try container.encode(fitMode, forKey: .fitMode)
        try container.encode(ocrLanguages, forKey: .ocrLanguages)
        try container.encode(splitPosition, forKey: .splitPosition)
        try container.encode(autoDetectSplit, forKey: .autoDetectSplit)
        try container.encode(readingOrder, forKey: .readingOrder)
    }
}
