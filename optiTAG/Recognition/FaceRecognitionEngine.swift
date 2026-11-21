import Foundation
import UIKit
import onnxruntime_objc

// One engine lives on the recognition queue; sessions never run on the UI thread.
final class FaceRecognitionEngine {
    enum Failure: LocalizedError {
        case invalidImage, faceCount(Int), missingModel(String), invalidOutput
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "無法解碼影像"
            case .faceCount(let count): return "影像需要恰好一張人臉（偵測到 \(count) 張）"
            case .missingModel(let name): return "找不到模型：\(name)"
            case .invalidOutput: return "模型輸出格式錯誤"
            }
        }
    }
    private let environment: ORTEnv
    private let detector: ORTSession
    private let recognizer: ORTSession
    private struct Face {
        let box: CGRect
        let score: Float
        let points: [CGPoint]
    }

    init() throws {
        environment = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        func path(_ name: String) throws -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: "onnx", subdirectory: "buffalo_s")
                    ?? Bundle.main.url(forResource: name, withExtension: "onnx") else { throw Failure.missingModel(name) }
            return url.path
        }
        detector = try ORTSession(env: environment, modelPath: path("det_500m"), sessionOptions: options)
        recognizer = try ORTSession(env: environment, modelPath: path("w600k_mbf"), sessionOptions: options)
    }

    private func infer(_ session: ORTSession, pixels: [Float], size: Int) throws -> [[Float]] {
        let data = pixels.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
        let tensor = try ORTValue(tensorData: data, elementType: .float, shape: [1, 3, NSNumber(value: size), NSNumber(value: size)])
        let inputs = try session.inputNames()
        let names = try session.outputNames()
        guard let input = inputs.first else { throw Failure.invalidOutput }
        let result = try session.run(withInputs: [input: tensor], outputNames: Set(names), runOptions: nil)
        return try names.map { name in
            guard let value = result[name] else { throw Failure.invalidOutput }
            let bytes = try value.tensorData() as Data
            return bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
    }

    // RGB NCHW, exactly the InsightFace blobFromImage normalization.
    private func pixels(_ image: UIImage, size: Int, transform: CGAffineTransform, mean: Float, scale: Float) throws -> [Float] {
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            context.cgContext.concatenate(transform)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cg = rendered.cgImage else { throw Failure.invalidImage }
        let success = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard success else { throw Failure.invalidImage }
        let plane = size * size
        var values = [Float](repeating: 0, count: plane * 3)
        for i in 0..<plane {
            for channel in 0..<3 { values[channel * plane + i] = (Float(rgba[i * 4 + channel]) - mean) / scale }
        }
        return values
    }

    func embedding(from data: Data) throws -> [Float] {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else { throw Failure.invalidImage }
        // The reference client adds a white border around the ESP32's tight face crops.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: source.size.width + 40, height: source.size.height + 40), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: source.size.width + 40, height: source.size.height + 40))
            source.draw(at: CGPoint(x: 20, y: 20))
        }
        let size = 640
        let ratio = min(CGFloat(size) / image.size.width, CGFloat(size) / image.size.height)
        let output = try infer(detector, pixels: pixels(image, size: size, transform: CGAffineTransform(scaleX: ratio, y: ratio), mean: 127.5, scale: 128), size: size)
        guard output.count == 9 else { throw Failure.invalidOutput }
        var candidates: [Face] = []
        for (level, stride) in [8, 16, 32].enumerated() {
            let scores = output[level], boxes = output[level + 3], landmarks = output[level + 6]
            let count = (size / stride) * (size / stride) * 2
            guard scores.count == count, boxes.count == count * 4, landmarks.count == count * 10 else { throw Failure.invalidOutput }
            let unit = CGFloat(stride) / ratio
            for i in 0..<count where scores[i] >= 0.5 {
                let anchor = i / 2
                let x = CGFloat(anchor % (size / stride)) * unit
                let y = CGFloat(anchor / (size / stride)) * unit
                let left = x - CGFloat(boxes[i * 4]) * unit, top = y - CGFloat(boxes[i * 4 + 1]) * unit
                let right = x + CGFloat(boxes[i * 4 + 2]) * unit, bottom = y + CGFloat(boxes[i * 4 + 3]) * unit
                let points = (0..<5).map { k in CGPoint(x: x + CGFloat(landmarks[i * 10 + k * 2]) * unit, y: y + CGFloat(landmarks[i * 10 + k * 2 + 1]) * unit) }
                candidates.append(Face(box: CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top)), score: scores[i], points: points))
            }
        }
        var faces: [Face] = []
        for face in candidates.sorted(by: { $0.score > $1.score }) {
            if !faces.contains(where: { previous in
                let intersection = face.box.intersection(previous.box)
                let overlap = intersection.isNull ? 0 : intersection.width * intersection.height
                let union = face.box.width * face.box.height + previous.box.width * previous.box.height - overlap
                return union > 0 && overlap / union > 0.4
            }) { faces.append(face) }
        }
        guard faces.count == 1 else { throw Failure.faceCount(faces.count) }
        let transform = try alignment(faces[0].points)
        let embedding = try infer(recognizer, pixels: pixels(image, size: 112, transform: transform, mean: 127.5, scale: 127.5), size: 112)
        guard let vector = embedding.first, vector.count == 512, vector.allSatisfy({ $0.isFinite }) else { throw Failure.invalidOutput }
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { throw Failure.invalidOutput }
        return vector.map { $0 / norm }
    }

    // Least-squares similarity transform to ArcFace's canonical five landmarks.
    private func alignment(_ points: [CGPoint]) throws -> CGAffineTransform {
        let target = [CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014),
                      CGPoint(x: 56.0252, y: 71.7366), CGPoint(x: 41.5493, y: 92.3655), CGPoint(x: 70.7299, y: 92.2041)]
        let sourceMean = CGPoint(x: points.reduce(0) { $0 + $1.x } / 5, y: points.reduce(0) { $0 + $1.y } / 5)
        let targetMean = CGPoint(x: target.reduce(0) { $0 + $1.x } / 5, y: target.reduce(0) { $0 + $1.y } / 5)
        var denominator: CGFloat = 0, a: CGFloat = 0, b: CGFloat = 0
        for (source, destination) in zip(points, target) {
            let x = source.x - sourceMean.x, y = source.y - sourceMean.y
            let u = destination.x - targetMean.x, v = destination.y - targetMean.y
            denominator += x * x + y * y; a += x * u + y * v; b += x * v - y * u
        }
        guard denominator > 0 else { throw Failure.invalidOutput }
        a /= denominator; b /= denominator
        return CGAffineTransform(a: a, b: b, c: -b, d: a,
            tx: targetMean.x - a * sourceMean.x + b * sourceMean.y,
            ty: targetMean.y - b * sourceMean.x - a * sourceMean.y)
    }
}
