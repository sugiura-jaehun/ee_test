import Foundation
import ImageIO
import Vision

let image = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["ja-JP", "en-US"]
request.regionOfInterest = CGRect(x: 0.05, y: 0.37, width: 0.9, height: 0.49)
let source = CGImageSourceCreateWithURL(image as CFURL, nil)!
let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: 1150
]
let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)!
try VNImageRequestHandler(cgImage: thumbnail).perform([request])

func compact(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines).joined()
}

let positions = (request.results ?? []).compactMap { result -> [Double]? in
    guard let text = result.topCandidates(1).first?.string,
          compact(text) == compact(label) else { return nil }
    return [Double(result.boundingBox.midX), 1 - Double(result.boundingBox.midY)]
}
let json = try JSONSerialization.data(withJSONObject: positions)
FileHandle.standardOutput.write(json)
