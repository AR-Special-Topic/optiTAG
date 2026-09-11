import Combine
import Foundation

final class MainViewModel: ObservableObject {
    @Published private(set) var logs: [RecognitionLog] = []
    @Published var databaseErrorMessage: String?
    @Published var ble = BLEManager()

    private let database: OptiTagDatabase
    private var cancellables: Set<AnyCancellable> = []

    init(database: OptiTagDatabase = .shared) {
        self.database = database
        ble.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        ble.onImageReceived = { [weak self] _, _, _ in
            self?.addRecognitionResult(
                personId: nil,
                name: "未知人物",
                tag: "未標記"
            )
        }
        loadRecentLogs()
    }

    func loadRecentLogs() {
        do {
            logs = try database.fetchRecentRecognitionLogs(limit: 10)
            databaseErrorMessage = nil
        } catch {
            databaseErrorMessage = "資料庫讀取失敗：\(error)"
        }
    }

    func addRecognitionResult(personId: Int64?, name: String, tag: String, confidence: Double? = nil) {
        do {
            try database.insertRecognitionLog(
                personId: personId,
                recognizedName: name,
                tag: tag,
                confidence: confidence
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
