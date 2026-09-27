import UIKit
import Vision
import CoreImage

final class ScanProcessingService {
    private let ciContext = CIContext(options: nil)

    /// 펼친 책을 지정된 제본선 비율을 기준으로 좌/우 두 페이지로 분리합니다.
    /// splitPosition은 0.0~1.0 범위이며, 0.5가 정확한 중앙입니다.
    func splitDoublePage(_ image: UIImage, splitPosition: Double = 0.5) -> [UIImage] {
        let upright = uprightImage(image)
        guard let cg = upright.cgImage else { return [upright] }

        let ratio = min(max(splitPosition, 0.35), 0.65)
        let width = cg.width
        let height = cg.height
        let splitX = min(max(Int((Double(width) * ratio).rounded()), 1), width - 1)

        guard
            let leftCG = cg.cropping(to: CGRect(x: 0, y: 0, width: splitX, height: height)),
            let rightCG = cg.cropping(to: CGRect(x: splitX, y: 0, width: width - splitX, height: height))
        else { return [upright] }

        return [
            UIImage(cgImage: leftCG, scale: 1, orientation: .up),
            UIImage(cgImage: rightCG, scale: 1, orientation: .up)
        ]
    }

    /// 중앙 38~62% 영역의 밝기를 저해상도로 분석해 제본선 후보를 찾습니다.
    /// 명확한 후보가 없으면 안전하게 0.5를 반환합니다.
    func suggestedSplitPosition(_ image: UIImage) -> Double {
        let upright = uprightImage(image)
        guard let cg = upright.cgImage else { return 0.5 }

        let sampleWidth = 240
        let sampleHeight = 180
        var pixels = [UInt8](repeating: 255, count: sampleWidth * sampleHeight)

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let baseAddress = buffer.baseAddress,
                let context = CGContext(
                    data: baseAddress,
                    width: sampleWidth,
                    height: sampleHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: sampleWidth,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else { return false }

            context.interpolationQuality = .low
            context.draw(cg, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }

        guard didDraw else { return 0.5 }

        let minX = Int(Double(sampleWidth) * 0.38)
        let maxX = Int(Double(sampleWidth) * 0.62)
        var columnAverage = [Double](repeating: 255, count: sampleWidth)

        for x in minX...maxX {
            var sum = 0
            for y in 0..<sampleHeight {
                sum += Int(pixels[y * sampleWidth + x])
            }
            columnAverage[x] = Double(sum) / Double(sampleHeight)
        }

        var bestX = sampleWidth / 2
        var bestScore = Double.greatestFiniteMagnitude
        let center = Double(sampleWidth) / 2.0

        for x in (minX + 2)...(maxX - 2) {
            let smoothed = (columnAverage[x - 2] + columnAverage[x - 1] + columnAverage[x] + columnAverage[x + 1] + columnAverage[x + 2]) / 5.0
            // 텍스트 열보다 중앙 제본선을 우선하도록 중앙에서 멀수록 작은 패널티를 줍니다.
            let score = smoothed + abs(Double(x) - center) * 0.12
            if score < bestScore {
                bestScore = score
                bestX = x
            }
        }

        let centralValues = (minX...maxX).map { columnAverage[$0] }.sorted()
        let median = centralValues[centralValues.count / 2]

        // 명확한 어두운 제본선이 없으면 중앙 분할이 더 안전합니다.
        guard median - bestScore >= 4.0 else { return 0.5 }

        let detected = Double(bestX) / Double(sampleWidth - 1)
        return min(max(detected, 0.42), 0.58)
    }

    /// 각 반쪽 페이지에서 큰 사각형을 찾으면 개별 원근 보정을 시도합니다.
    /// 검출이 불확실하면 원본을 그대로 반환하므로 스캔 실패로 이어지지 않습니다.
    func correctPerspective(_ image: UIImage) -> UIImage {
        let upright = uprightImage(image)
        guard let cg = upright.cgImage else { return upright }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.45
        request.minimumAspectRatio = 0.30
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.45
        request.quadratureTolerance = 28

        do {
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([request])
        } catch {
            return upright
        }

        guard
            let observation = request.results?.first as? VNRectangleObservation,
            observation.boundingBox.width * observation.boundingBox.height >= 0.50
        else { return upright }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)

        func point(_ normalized: CGPoint) -> CGPoint {
            CGPoint(x: normalized.x * width, y: normalized.y * height)
        }

        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return upright }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: point(observation.topLeft)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: point(observation.topRight)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: point(observation.bottomLeft)), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: point(observation.bottomRight)), forKey: "inputBottomRight")

        guard
            let output = filter.outputImage,
            !output.extent.isEmpty,
            let correctedCG = ciContext.createCGImage(output, from: output.extent)
        else { return upright }

        return UIImage(cgImage: correctedCG, scale: 1, orientation: .up)
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

    /// 모든 페이지를 첫 페이지에서 정한 동일 캔버스 크기로 정규화합니다.
    func normalize(_ image: UIImage, profile: ScanProfile) -> UIImage {
        let upright = uprightImage(image)
        let targetSize = CGSize(width: CGFloat(profile.outputWidthPixels), height: CGFloat(profile.outputHeightPixels))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let source = upright.size
            guard source.width > 0, source.height > 0 else { return }

            let scaleX = targetSize.width / source.width
            let scaleY = targetSize.height / source.height
            let scale: CGFloat = profile.fitMode == .aspectFit ? min(scaleX, scaleY) : max(scaleX, scaleY)
            let drawSize = CGSize(width: source.width * scale, height: source.height * scale)
            let origin = CGPoint(x: (targetSize.width - drawSize.width) / 2, y: (targetSize.height - drawSize.height) / 2)
            upright.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    private func uprightImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
