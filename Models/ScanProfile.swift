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

    var captureMode: CaptureMode
    /// width / height
    var pageAspectRatio: Double
    /// 저장용 기준 폭(px). 높이는 aspect ratio로 계산합니다.
    var outputWidthPixels: Int
    var fitMode: FitMode
    var ocrLanguages: [String]

    var outputHeightPixels: Int {
        guard pageAspectRatio > 0 else { return outputWidthPixels }
        return Int((Double(outputWidthPixels) / pageAspectRatio).rounded())
    }

    static let initial = ScanProfile(
        captureMode: .doublePage,
        pageAspectRatio: 0.70,
        outputWidthPixels: 1800,
        fitMode: .aspectFit,
        ocrLanguages: ["ko-KR", "en-US"]
    )
}
