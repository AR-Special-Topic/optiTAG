import Foundation

/// Idempotent cleanup of both local copies; a restart can finish a partial deletion.
enum ConversationAudioCleanup {
    static func remove(event: ConversationEvent, root: URL) throws {
        let working = root.appendingPathComponent(event.deviceID + "_" + event.eventID + ".wav")
        let cached = root.deletingLastPathComponent().appendingPathComponent("SDExport")
            .appendingPathComponent(event.deviceID).appendingPathComponent("files").appendingPathComponent(event.audioPath)
        for url in [working, cached] {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
