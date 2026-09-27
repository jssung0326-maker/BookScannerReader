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

    /// 페이지 외곽 사각형 검출 및 원근 보정을 사용합니다.
    var geometryCorrectionEnabled: Bool
    /// 펼친 책 중앙부의 곡면 왜곡을 완화하는 1차 보정 강도(0...1).
    var dewarpStrength: Double
    /// 제본부 그림자/검은 여백 자동 제거 사용 여부입니다.
    var trimSpineShadow: Bool

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
        readingOrder: ReadingOrder = .leftToRight,
        geometryCorrectionEnabled: Bool = true,
        dewarpStrength: Double = 0.35,
        trimSpineShadow: Bool = true
    ) {
        self.captureMode = captureMode
        self.pageAspectRatio = pageAspectRatio
        self.outputWidthPixels = outputWidthPixels
        self.fitMode = fitMode
        self.ocrLanguages = ocrLanguages
        self.splitPosition = min(max(splitPosition, 0.35), 0.65)
        self.autoDetectSplit = autoDetectSplit
        self.readingOrder = readingOrder
        self.geometryCorrectionEnabled = geometryCorrectionEnabled
        self.dewarpStrength = min(max(dewarpStrength, 0.0), 1.0)
        self.trimSpineShadow = trimSpineShadow
    }

    static let initial = ScanProfile(
        captureMode: .doublePage,
        pageAspectRatio: 0.70,
        outputWidthPixels: 1800,
        fitMode: .aspectFit,
        ocrLanguages: ["ko-KR", "en-US"],
        splitPosition: 0.5,
        autoDetectSplit: true,
        readingOrder: .leftToRight,
        geometryCorrectionEnabled: true,
        dewarpStrength: 0.35,
        trimSpineShadow: true
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
        case geometryCorrectionEnabled
        case dewarpStrength
        case trimSpineShadow
    }

    /// v0.2/v0.3에서 저장한 ScanProfile에도 새 기본값을 넣어 그대로 열 수 있도록 합니다.
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
        geometryCorrectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .geometryCorrectionEnabled) ?? true
        dewarpStrength = min(max(try container.decodeIfPresent(Double.self, forKey: .dewarpStrength) ?? 0.35, 0.0), 1.0)
        trimSpineShadow = try container.decodeIfPresent(Bool.self, forKey: .trimSpineShadow) ?? true
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
        try container.encode(geometryCorrectionEnabled, forKey: .geometryCorrectionEnabled)
        try container.encode(dewarpStrength, forKey: .dewarpStrength)
        try container.encode(trimSpineShadow, forKey: .trimSpineShadow)
    }
}
