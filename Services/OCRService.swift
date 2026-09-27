import Foundation
import UIKit
import Vision

final class OCRService {
    struct Result {
        let text: String
        let blocks: [OCRBlock]
    }

    func recognize(image: UIImage, languages: [String]) async throws -> String {
        try await recognizeDetailed(image: image, languages: languages).text
    }

    func recognizeDetailed(image: UIImage, languages: [String]) async throws -> Result {
        guard let cgImage = image.cgImage else { return Result(text: "", blocks: []) }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var lines: [String] = []
                var blocks: [OCRBlock] = []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    lines.append(candidate.string)
                    let box = observation.boundingBox
                    blocks.append(
                        OCRBlock(
                            text: candidate.string,
                            x: box.origin.x,
                            y: box.origin.y,
                            width: box.size.width,
                            height: box.size.height
                        )
                    )
                }

                continuation.resume(returning: Result(text: lines.joined(separator: "\n"), blocks: blocks))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
