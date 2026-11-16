import Foundation

final class RecognitionWorker {
    private let queue = DispatchQueue(label: "optiTAG.recognition", qos: .userInitiated)
    private var engine: FaceRecognitionEngine?

    func embedding(from data: Data, completion: @escaping (Result<[Float], Error>) -> Void) {
        queue.async { [self] in
            let result = Result { () throws -> [Float] in
                if engine == nil { engine = try FaceRecognitionEngine() }
                return try engine!.embedding(from: data)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
