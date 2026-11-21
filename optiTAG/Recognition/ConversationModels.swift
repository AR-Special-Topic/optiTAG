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
    var contentDeleted: Bool?
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
    var sourceSnapshots: [ConversationEvent]? = nil
    var workKeys: [String]? = nil
}

struct SummaryInput: Encodable {
    let eventID: String
    let deviceID: String
    let boot: String
    let segments: [TranscriptSegment]
    let people: [[String: String]]
    init(_ event: ConversationEvent) {
        eventID = event.id; deviceID = event.deviceID; boot = event.boot
        segments = event.segments; people = event.faceAssociations
    }
}

struct SummaryWork: Codable {
    let key: String
    let event: ConversationEvent
}

enum SummaryBatching {
    static let byteLimit = 128 * 1024
    static func size(_ events: [ConversationEvent], prompt: String) throws -> Int {
        try JSONEncoder().encode(events.map(SummaryInput.init)).count + prompt.utf8.count + 128
    }
    static func batches(_ work: [SummaryWork], prompt: String) throws -> [[SummaryWork]] {
        var result: [[SummaryWork]] = []
        for item in work {
            if let last = result.last,
               !last.contains(where: { $0.event.id == item.event.id }),
               try size(last.map(\.event) + [item.event], prompt: prompt) <= byteLimit {
                result[result.count - 1].append(item)
            } else { result.append([item]) }
        }
        return result
    }
    static func fragments(_ event: ConversationEvent, prompt: String) throws -> [SummaryWork] {
        var result: [SummaryWork] = []
        var current = event; current.segments = []
        func commit() {
            guard !current.segments.isEmpty else { return }
            result.append(SummaryWork(key: event.id + "#" + String(result.count), event: current))
            current.segments = []
        }
        // Split large text before packing; preserve evidence bounds on each piece.
        for segment in event.segments {
            var text = ""
            for character in segment.text {
                text.append(character)
                if text.utf8.count >= 8192 {
                    let piece = TranscriptSegment(start: segment.start, end: segment.end, text: text)
                    var candidate = current; candidate.segments.append(piece)
                    if try size([candidate], prompt: prompt) > byteLimit { commit() }
                    current.segments.append(piece); text = ""
                    guard try size([current], prompt: prompt) <= byteLimit else { throw PersonError.message("單筆人物資料超過彙整長度限制") }
                }
            }
            if !text.isEmpty {
                let piece = TranscriptSegment(start: segment.start, end: segment.end, text: text)
                var candidate = current; candidate.segments.append(piece)
                if try size([candidate], prompt: prompt) > byteLimit { commit() }
                current.segments.append(piece)
                guard try size([current], prompt: prompt) <= byteLimit else { throw PersonError.message("單筆人物資料超過彙整長度限制") }
            }
        }
        commit(); return result
    }
}

struct EventImageContext {
    let deviceID: String
    let eventID: String
    let faceIndex: UInt16
    let faceCount: UInt16
}
