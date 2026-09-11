import Foundation

struct RecognitionLog: Identifiable, Equatable {
    let id: Int64
    var personId: Int64?
    var name: String
    var tag: String
    var confidence: Double?
    var recognizedAt: Date

    var isUnknown: Bool {
        personId == nil || name == "未知人物"
    }

    var initial: String {
        guard let firstCharacter = name.first, !isUnknown else {
            return "?"
        }
        return String(firstCharacter)
    }
}
