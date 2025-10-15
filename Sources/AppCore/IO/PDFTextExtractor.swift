import Foundation
import CoreGraphics
import PDFKit
import Vision

enum PDFTextExtractor {
    static func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.failedToOpen(url)
        }

        var collected: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let attributed = page.attributedString, attributed.string.trimmedIfNeeded().isEmpty == false {
                collected.append(attributed.string)
            } else if let image = render(page: page) {
                let recognized = try recognizeText(in: image)
                if !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    collected.append(recognized)
                }
            }
        }
        return collected.joined(separator: "\n\n")
    }

    private static func render(page: PDFPage) -> CGImage? {
        guard let pageRef = page.pageRef else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(pageRef)

        return context.makeImage()
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let strings = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        return strings.joined(separator: "\n")
    }

    enum ExtractionError: Error {
        case failedToOpen(URL)
    }
}

private extension String {
    func trimmedIfNeeded() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
