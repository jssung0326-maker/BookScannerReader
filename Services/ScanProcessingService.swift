import UIKit
import Vision
import CoreImage

final class ScanProcessingService {
    enum PageSide: Equatable {
        case single
        case left
        case right
    }

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

    /// v0.4 제본선 탐지: 중앙 34~66% 범위의 밝기, 국소 대비, 중앙 우선도를 함께 평가합니다.
    /// 어두운 제본선뿐 아니라 밝은 종이 사이의 강한 수직 경계도 후보로 잡을 수 있습니다.
    func suggestedSplitPosition(_ image: UIImage) -> Double {
        let upright = uprightImage(image)
        guard let cg = upright.cgImage else { return 0.5 }

        let sampleWidth = 320
        let sampleHeight = 220
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

        let minX = Int(Double(sampleWidth) * 0.34)
        let maxX = Int(Double(sampleWidth) * 0.66)
        var mean = [Double](repeating: 255, count: sampleWidth)
        var variance = [Double](repeating: 0, count: sampleWidth)

        // 상하 가장자리의 배경 영향을 줄이기 위해 가운데 84%만 분석합니다.
        let minY = Int(Double(sampleHeight) * 0.08)
        let maxY = Int(Double(sampleHeight) * 0.92)
        let countY = max(maxY - minY, 1)

        for x in minX...maxX {
            var sum = 0.0
            var sumSquares = 0.0
            for y in minY..<maxY {
                let value = Double(pixels[y * sampleWidth + x])
                sum += value
                sumSquares += value * value
            }
            let m = sum / Double(countY)
            mean[x] = m
            variance[x] = max(0, sumSquares / Double(countY) - m * m)
        }

        let center = Double(sampleWidth - 1) / 2.0
        var bestX = sampleWidth / 2
        var bestScore = -Double.greatestFiniteMagnitude

        for x in (minX + 3)...(maxX - 3) {
            let localMean = (mean[x - 1] + mean[x] + mean[x + 1]) / 3.0
            let leftMean = (mean[x - 3] + mean[x - 2]) / 2.0
            let rightMean = (mean[x + 2] + mean[x + 3]) / 2.0

            let darkness = max(0, 220.0 - localMean) / 220.0
            let edgeContrast = abs(rightMean - leftMean) / 255.0
            let texturePenalty = min(1.0, sqrt(variance[x]) / 64.0)
            let centerDistance = abs(Double(x) - center) / (Double(sampleWidth) * 0.16)
            let centerPrior = max(0, 1.0 - centerDistance)

            // 제본부는 일반적으로 중앙에 가깝고, 어둡거나 좌우 밝기 변화가 크며,
            // 텍스트 열처럼 세로 방향 분산이 지나치게 크지 않은 경향이 있습니다.
            let score = darkness * 0.46
                + edgeContrast * 0.32
                + centerPrior * 0.30
                - texturePenalty * 0.10

            if score > bestScore {
                bestScore = score
                bestX = x
            }
        }

        // 후보가 약하면 50% 중앙값이 더 안전합니다.
        guard bestScore >= 0.23 else { return 0.5 }

        let detected = Double(bestX) / Double(sampleWidth - 1)
        return min(max(detected, 0.40), 0.60)
    }

    /// 페이지 외곽 사각형을 여러 개 검출한 뒤 면적·중앙 정렬·신뢰도를 함께 평가합니다.
    func correctPerspective(_ image: UIImage) -> UIImage {
        let upright = uprightImage(image)
        guard let cg = upright.cgImage else { return upright }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumConfidence = 0.30
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.32
        request.quadratureTolerance = 35

        do {
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([request])
        } catch {
            return upright
        }

        guard let observations = request.results, !observations.isEmpty else { return upright }

        let center = CGPoint(x: 0.5, y: 0.5)
        let best = observations.max { lhs, rhs in
            rectangleScore(lhs, center: center) < rectangleScore(rhs, center: center)
        }

        guard
            let observation = best,
            observation.boundingBox.width * observation.boundingBox.height >= 0.34
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

    /// 한 페이지에 적용할 v0.4의 전체 보정 파이프라인입니다.
    /// 원근 보정 → 제본부 그림자/검은 여백 제거 → 가벼운 곡면 보정 순서입니다.
    func preparePage(
        _ image: UIImage,
        side: PageSide,
        geometryCorrectionEnabled: Bool,
        dewarpStrength: Double,
        trimSpineShadow: Bool
    ) -> UIImage {
        var result = uprightImage(image)

        if geometryCorrectionEnabled {
            result = correctPerspective(result)
        }

        if trimSpineShadow, side != .single {
            result = trimInnerSpineShadow(result, side: side)
        }

        let strength = min(max(dewarpStrength, 0.0), 1.0)
        if side != .single, strength > 0.01 {
            result = dewarpBookPageLite(result, side: side, strength: strength)
        }

        return result
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

    private func rectangleScore(_ observation: VNRectangleObservation, center: CGPoint) -> Double {
        let box = observation.boundingBox
        let area = Double(box.width * box.height)
        let boxCenter = CGPoint(x: box.midX, y: box.midY)
        let centerDistance = hypot(Double(boxCenter.x - center.x), Double(boxCenter.y - center.y))
        let centering = max(0.0, 1.0 - centerDistance * 1.8)
        let confidence = Double(observation.confidence)
        return area * 0.62 + centering * 0.22 + confidence * 0.16
    }

    /// 분리 직후 제본부에 남는 짙은 그림자/검은 여백을 최대 약 7%까지 자동 제거합니다.
    private func trimInnerSpineShadow(_ image: UIImage, side: PageSide) -> UIImage {
        let upright = uprightImage(image)
        guard let cg = upright.cgImage else { return upright }

        let width = cg.width
        let height = cg.height
        guard width > 120, height > 120 else { return upright }

        let sampleWidth = min(180, width)
        let sampleHeight = min(220, height)
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

        guard didDraw else { return upright }

        let maxTrimFraction = 0.07
        let maxTrimColumns = max(1, Int(Double(sampleWidth) * maxTrimFraction))
        let centerY0 = Int(Double(sampleHeight) * 0.12)
        let centerY1 = Int(Double(sampleHeight) * 0.88)
        let countY = max(centerY1 - centerY0, 1)

        func columnAverage(_ x: Int) -> Double {
            var sum = 0
            for y in centerY0..<centerY1 {
                sum += Int(pixels[y * sampleWidth + x])
            }
            return Double(sum) / Double(countY)
        }

        var trimColumns = 0
        switch side {
        case .left:
            // 왼쪽 페이지의 안쪽은 오른쪽 가장자리입니다.
            for offset in 0..<maxTrimColumns {
                let x = sampleWidth - 1 - offset
                let avg = columnAverage(x)
                if avg < 150 {
                    trimColumns = offset + 1
                } else if offset >= 2 {
                    break
                }
            }
        case .right:
            // 오른쪽 페이지의 안쪽은 왼쪽 가장자리입니다.
            for x in 0..<maxTrimColumns {
                let avg = columnAverage(x)
                if avg < 150 {
                    trimColumns = x + 1
                } else if x >= 2 {
                    break
                }
            }
        case .single:
            return upright
        }

        guard trimColumns > 0 else { return upright }

        let fraction = Double(trimColumns) / Double(sampleWidth)
        let actualTrim = min(Int((Double(width) * fraction).rounded()), Int(Double(width) * maxTrimFraction))
        guard actualTrim > 0, actualTrim < width - 10 else { return upright }

        let cropRect: CGRect
        switch side {
        case .left:
            cropRect = CGRect(x: 0, y: 0, width: width - actualTrim, height: height)
        case .right:
            cropRect = CGRect(x: actualTrim, y: 0, width: width - actualTrim, height: height)
        case .single:
            return upright
        }

        guard let cropped = cg.cropping(to: cropRect) else { return upright }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// v0.4 1차 곡면 보정.
    /// 제본부 가까운 영역을 가볍게 수평 확장해 글자가 안쪽으로 눌리는 현상을 완화합니다.
    /// 완전한 3D dewarp가 아니라 안전한 2D 비선형 리매핑입니다.
    private func dewarpBookPageLite(_ image: UIImage, side: PageSide, strength: Double) -> UIImage {
        let upright = uprightImage(image)
        guard let cg = upright.cgImage else { return upright }

        let width = cg.width
        let height = cg.height
        guard width >= 240, height >= 240 else { return upright }

        let clampedStrength = min(max(strength, 0.0), 1.0)
        let gamma = 1.0 + clampedStrength * 0.28
        let stripCount = min(120, max(48, width / 18))
        let targetSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.interpolationQuality = .high
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            for index in 0..<stripCount {
                let t0 = Double(index) / Double(stripCount)
                let t1 = Double(index + 1) / Double(stripCount)

                let s0: Double
                let s1: Double
                switch side {
                case .left:
                    // 왼쪽 페이지: 안쪽(오른쪽)을 더 넓게 펼칩니다.
                    s0 = 1.0 - pow(1.0 - t0, gamma)
                    s1 = 1.0 - pow(1.0 - t1, gamma)
                case .right:
                    // 오른쪽 페이지: 안쪽(왼쪽)을 더 넓게 펼칩니다.
                    s0 = pow(t0, gamma)
                    s1 = pow(t1, gamma)
                case .single:
                    s0 = t0
                    s1 = t1
                }

                let sourceX0 = min(max(Int((Double(width) * s0).rounded(.down)), 0), width - 1)
                let sourceX1 = min(max(Int((Double(width) * s1).rounded(.up)), sourceX0 + 1), width)
                let sourceRect = CGRect(x: CGFloat(sourceX0), y: 0, width: CGFloat(sourceX1 - sourceX0), height: CGFloat(height))

                guard let strip = cg.cropping(to: sourceRect) else { continue }

                let targetX0 = CGFloat(index) * CGFloat(width) / CGFloat(stripCount)
                let targetX1 = CGFloat(index + 1) * CGFloat(width) / CGFloat(stripCount)
                let targetRect = CGRect(x: targetX0, y: 0, width: targetX1 - targetX0 + 0.75, height: CGFloat(height))
                context.draw(strip, in: targetRect)
            }
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
