import Foundation
import Vision

public enum TextRecognizer {
    /// Reads the text in an image (screenshot, photo of a page, etc.) entirely on this Mac.
    /// Blocks while Vision works, so call it off the main thread.
    public static func recognize(imageAt url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(url: url, options: [:]).perform([request])

        let observations = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }   // top to bottom
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
