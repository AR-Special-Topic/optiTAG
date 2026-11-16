import Combine
import Foundation

@MainActor final class MainViewModel: ObservableObject {
    @Published private(set) var logs: [RecognitionLog] = []
    @Published var databaseErrorMessage: String?
    @Published var ble = BLEManager()

    @Published private(set) var recognitionStatus = "請先新增人物照片"
    @Published private(set) var enrolledCount = 0
    @Published private(set) var isEnrolling = false
    @Published private(set) var enrollmentRevision = 0
    private let worker = RecognitionWorker()
    private let threshold: Float = 0.45
    private let database: OptiTagDatabase
    private var cancellables: Set<AnyCancellable> = []

    init(database: OptiTagDatabase = .shared) {
        self.database = database
        ble.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        ble.onImageReceived = { [weak self] request, image, data, context in
            self?.recognize(data, requestID: request, imageID: image, context: context)
        }
        refreshEnrollmentCount()
        loadRecentLogs()
    }

    func refreshEnrollmentCount() {
        do { enrolledCount = try database.fetchPersons().count }
        catch { databaseErrorMessage = error.localizedDescription }
    }

    func enroll(data: Data, name: String, tag: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isEnrolling else { return }
        isEnrolling = true
        recognitionStatus = "正在建立人物特徵…"
        worker.embedding(from: data) { [weak self] result in
            guard let self else { return }
            defer { self.isEnrolling = false }
            do {
                let embedding = try result.get()
                try self.database.enrollFace(name: name, tag: tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未標記" : tag.trimmingCharacters(in: .whitespacesAndNewlines), embedding: embedding)
                self.refreshEnrollmentCount()
                self.enrollmentRevision += 1
                self.recognitionStatus = "已新增：\(name)"
            } catch { self.recognitionStatus = error.localizedDescription }
        }
    }

    private func recognize(_ data: Data, requestID: UInt32, imageID: UInt32, context: EventImageContext?) {
        let generation = ble.connectionGeneration
        let started = Date()
        recognitionStatus = "正在辨識…"
        worker.embedding(from: data) { [weak self] result in
            guard let self else { return }
            var status: StatusCode = .unknown
            var person: OptiTagDatabase.FaceSample?
            var similarity: Float = 0
            do {
                let vector = try result.get()
                let samples = try self.database.fetchFaceSamples()
                let best = samples.map { sample in
                    (sample, zip(vector, sample.embedding).reduce(Float(0)) { $0 + $1.0 * $1.1 })
                }.max { $0.1 < $1.1 }
                similarity = best?.1 ?? 0
                if let best, best.1 >= self.threshold { person = best.0; status = .ok }
                self.recognitionStatus = person.map { "辨識結果：\($0.name)（相似度 \(String(format: "%.2f", similarity))）" } ?? "未知人物（尚未登錄或相似度不足）"
            } catch {
                if case FaceRecognitionEngine.Failure.faceCount(let count) = error, count == 0 { status = .noFace }
                else { status = .failed }
                self.recognitionStatus = error.localizedDescription
            }
            let elapsed = UInt32(min(Double(UInt32.max), max(0, Date().timeIntervalSince(started) * 1000)))
            if let context {
                let states: [StatusCode: String] = [.ok: "RECOGNIZED", .unknown: "UNKNOWN", .noFace: "CLIENT_NO_FACE", .failed: "FAILED"]
                self.ble.onEventFace?(context.deviceID, context.eventID, [
                    "event_id": context.eventID, "request_id": String(requestID), "image_id": String(imageID),
                    "face_index": String(context.faceIndex), "face_count": String(context.faceCount),
                    "person_id": person.map { String($0.personID) } ?? "", "name": person?.name ?? "未知人物",
                    "tag": person?.tag ?? "未標記", "similarity": String(similarity),
                    "status": states[status] ?? "FAILED", "processing_time_ms": String(elapsed)])
                self.loadRecentLogs()
            } else if status == .ok || status == .unknown {
                self.addRecognitionResult(personId: person?.personID, name: person?.name ?? "未知人物",
                    tag: person?.tag ?? "未標記", confidence: Double(similarity))
            }
            self.ble.sendRecognitionResult(RecognitionResult(requestID: requestID, imageID: imageID, status: status,
                personID: person.map { String($0.personID) } ?? "", personName: person?.name ?? "UNKNOWN",
                similarity: similarity, processingTimeMs: elapsed), generation: generation)
        }
    }

    func loadRecentLogs() {
        do {
            logs = try database.fetchRecentRecognitionLogs(limit: 10)
            databaseErrorMessage = nil
        } catch {
            databaseErrorMessage = "資料庫讀取失敗：\(error)"
        }
    }

    func addRecognitionResult(personId: Int64?, name: String, tag: String, confidence: Double? = nil, eventKey: String? = nil, sourceKey: String? = nil) {
        do {
            try database.insertRecognitionLog(
                personId: personId,
                recognizedName: name,
                tag: tag,
                confidence: confidence, eventKey: eventKey, sourceKey: sourceKey
            )
            loadRecentLogs()
        } catch {
            databaseErrorMessage = "辨識紀錄儲存失敗：\(error)"
        }
    }

    func startBLEScanOrCapture() {
        ble.scanOrCapture()
    }
}
