import Foundation

struct TranscriptSegment: Codable, Hashable {
    let start: Double
    let end: Double
    let text: String
}

struct ConversationEvent: Codable, Identifiable {
    var id: String { deviceID + ":" + eventID }
    let deviceID: String
    let eventID: String
    let firstSample: UInt64
    let vadStartSample: UInt64
    let vadStartUs: Int64
    let endUs: Int64
    let audioPath: String
    var audioSHA256 = ""
    var faceAssociations: [[String: String]] = []
    var lifecycle: [[String: String]] = []
    var segments: [TranscriptSegment] = []
    var state = "待轉寫"
    var error: String?
    var localAudioDeleted = false
    var deviceAudioDeleted = false
    // Optional for compatibility with events saved before no-speech handling.
    var noSpeech: Bool?
    var isNoSpeech: Bool { noSpeech == true }

    mutating func applySuccessfulTranscription(_ result: [TranscriptSegment]) {
        segments = result.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        noSpeech = segments.isEmpty
        state = isNoSpeech ? "未辨識到語音" : "已轉寫"
        error = nil
    }

    // esp_timer is relative to boot, never a calendar date.
    var boot: String { String(eventID.prefix(8)) }
    func bootSeconds(_ offset: Double) -> Double {
        Double(vadStartUs) / 1_000_000 + (Double(firstSample) - Double(vadStartSample)) / 16_000 + offset
    }
}

struct ConversationSummary: Codable, Identifiable {
    let id: String
    let sourceIDs: [String]
    let createdAt: Date
    let title: String
    let overview: String
    let decisions: [String]
    let tasks: [String]
    let questions: [String]
}
