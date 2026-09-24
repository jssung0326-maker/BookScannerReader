import UIKit

final class ScanProcessingService {
    /// 1차 구현: 두 페이지 펼침 이미지를 중앙 기준으로 좌/우 분리.
    /// 후속 버전에서 제본선 자동 검출 + 좌/우 독립 원근/곡면 보정으로 교체할 예정입니다.
    func splitDoublePage(_ image: UIImage) -> [UIImage] {
        guard let cg = image.cgImage else { return [image] }
        let width = cg.width
        let height = cg.height
        let mid = width / 2

        guard
            let leftCG = cg.cropping(to: CGRect(x: 0, y: 0, width: mid, height: height)),
            let rightCG = cg.cropping(to: CGRect(x: mid, y: 0, width: width - mid, height: height))
        else { return [image] }

        return [
            UIImage(cgImage: leftCG, scale: image.scale, orientation: image.imageOrientation),
            UIImage(cgImage: rightCG, scale: image.scale, orientation: image.imageOrientation)
        ]
    }

    func inferredProfile(from image: UIImage, captureMode: ScanProfile.CaptureMode) -> ScanProfile {
        let size = image.size
        let ratio = max(0.2, min(5.0, Double(size.width / max(size.height, 1))))
        return ScanProfile(
            captureMode: captureMode,
            pageAspectRatio: ratio,
            outputWidthPixels: 1800,
            fitMode: .aspectFit,
            ocrLanguages: ["ko-KR", "en-US"]
        )
    }

    func normalize(_ image: UIImage, profile: ScanProfile) -> UIImage {
        let targetSize = CGSize(width: CGFloat(profile.outputWidthPixels), height: CGFloat(profile.outputHeightPixels))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let source = image.size
            guard source.width > 0, source.height > 0 else { return }

            let scaleX = targetSize.width / source.width
            let scaleY = targetSize.height / source.height
            let scale: CGFloat = profile.fitMode == .aspectFit ? min(scaleX, scaleY) : max(scaleX, scaleY)
            let drawSize = CGSize(width: source.width * scale, height: source.height * scale)
            let origin = CGPoint(x: (targetSize.width - drawSize.width) / 2, y: (targetSize.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
