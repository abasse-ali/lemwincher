import Foundation
import UIKit
import Vision
import ImageIO

/// Lecture du texte et des codes-barres sur une photo (étiquette de prix, ticket de caisse), sur l'iPhone.
enum TextRecognizer {
    /// Texte reconnu (français), avec la position de chaque morceau.
    static func recognize(_ image: UIImage) async -> [RecognizedText] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["fr-FR", "en-US"]
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                let observations: [VNRecognizedTextObservation] = request.results ?? []
                let pieces = observations.compactMap { observation -> RecognizedText? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedText(text: candidate.string, box: observation.boundingBox)
                }
                continuation.resume(returning: pieces)
            }
        }
    }

    /// Codes-barres EAN / UPC visibles sur la photo.
    static func barcodes(_ image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.ean13, .ean8, .upce]
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                let observations: [VNBarcodeObservation] = request.results ?? []
                let codes = observations.compactMap { $0.payloadStringValue }.filter { $0.isBarcodeLike }
                continuation.resume(returning: Array(Set(codes)))
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
