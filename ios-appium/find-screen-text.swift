import Foundation
import Vision

let image = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["ja-JP", "en-US"]
try VNImageRequestHandler(url: image).perform([request])

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
