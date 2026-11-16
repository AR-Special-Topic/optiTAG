import Foundation

enum PersonError: Error { case message(String) }

@main struct ConversationChecks {
    static func main() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try ConversationRepository(url: url)
        var event = ConversationEvent(deviceID: "test-device", eventID: "0000002500000068", firstSample: 8000, vadStartSample: 16000, vadStartUs: 2000000, endUs: 4000000, audioPath: "event_0000002500000068.wav")
        precondition(event.bootSeconds(0) == 1.5) // Pre-roll uses audio_first_sample, not VAD offset zero.
        precondition(event.boot == "00000025")
        event.segments = [TranscriptSegment(start: 0.5, end: 1, text: "週五交報告")]
        try repository.save(events: [event], summaries: [])
        let before = try repository.unfinished()
        precondition(before.count == 1)
        let summary = ConversationSummary(id: "summary", sourceIDs: [event.id], createdAt: Date(), title: "報告", overview: "週五交報告", decisions: [], tasks: ["週五交報告"], questions: [])
        try repository.save(events: [], summaries: [summary])
        let summarized = try repository.hasSummary(eventID: event.id)
        precondition(summarized)
        // Simulate restart after summary commit but before audio deletion.
        let restarted = try ConversationRepository(url: url)
        let pending = try restarted.unfinished()
        let hasSummary = try restarted.hasSummary(eventID: event.id)
        precondition(pending.count == 1 && hasSummary)
        event.localAudioDeleted = true
        try repository.save(events: [event], summaries: [summary])
        let unfinished = try repository.unfinished()
        let cleanup = try repository.cleanup(deviceID: "test-device")
        precondition(unfinished.isEmpty && cleanup.count == 1)
        let matches = try repository.summaries(search: "週五", limit: 1)
        let literal = try repository.summaries(search: "%")
        precondition(matches.count == 1 && literal.isEmpty)
        let bad = ConversationSummary(id: "bad", sourceIDs: ["missing"], createdAt: Date(), title: "bad", overview: "bad", decisions: [], tasks: [], questions: [])
        do { try repository.save(events: [], summaries: [bad]); fatalError("Expected FK rejection") } catch {}
        let all = try repository.summaries()
        precondition(all.count == 1) // Transaction rollback removes orphan summary.
        let sources = try repository.sources(summaryID: "summary")
        precondition(sources[0].eventID == "0000002500000068" && sources[0].segments[0].text == "週五交報告")
        // An empty successful STT response is terminal, without an AI summary.
        let filesRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: filesRoot) }
        let root = filesRoot.appendingPathComponent("Conversations")
        let cache = filesRoot.appendingPathComponent("SDExport/test-device/files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var silent = ConversationEvent(deviceID: "test-device", eventID: "0000002500000069", firstSample: 0, vadStartSample: 0, vadStartUs: 0, endUs: 1000000, audioPath: "event_0000002500000069.wav")
        let working = root.appendingPathComponent("test-device_" + silent.eventID + ".wav")
        let cached = cache.appendingPathComponent(silent.audioPath)
        try Data([1, 2]).write(to: working)
        try Data([1, 2]).write(to: cached)
        silent.applySuccessfulTranscription([TranscriptSegment(start: 0, end: 1, text: " \n\t")])
        precondition(silent.isNoSpeech && silent.segments.isEmpty && silent.error == nil)
        try repository.save(events: [silent], summaries: [])
        let savedSilent = try ConversationRepository(url: url).event(id: silent.id)!
        precondition(savedSilent.isNoSpeech && !savedSilent.localAudioDeleted)
        let silentHasSummary = try repository.hasSummary(eventID: silent.id)
        precondition(!silentHasSummary)
        try ConversationAudioCleanup.remove(event: savedSilent, root: root)
        precondition(!FileManager.default.fileExists(atPath: working.path))
        precondition(!FileManager.default.fileExists(atPath: cached.path))
        try ConversationAudioCleanup.remove(event: savedSilent, root: root) // Safe after a partial cleanup/restart.
        silent.localAudioDeleted = true
        try repository.save(events: [silent], summaries: [])
        var next = ConversationEvent(deviceID: "test-device", eventID: "000000250000006A", firstSample: 0, vadStartSample: 0, vadStartUs: 1000000, endUs: 2000000, audioPath: "event_000000250000006A.wav")
        try repository.save(events: [next], summaries: [])
        let nextQueue = try repository.unfinished()
        precondition(nextQueue.map(\.id) == [next.id])
        let silentCleanup = try repository.cleanup(deviceID: "test-device")
        precondition(silentCleanup.contains { $0.id == silent.id })
        next.applySuccessfulTranscription([TranscriptSegment(start: 0, end: 1, text: "有語音")])
        precondition(!next.isNoSpeech && !next.segments.isEmpty)
        // Old stored events have no noSpeech key and remain retryable.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(next)) as! [String: Any]
        legacy.removeValue(forKey: "noSpeech")
        let restored = try JSONDecoder().decode(ConversationEvent.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(!restored.isNoSpeech)
        print("Conversation checks passed: persistence, search, rollback, no-speech cleanup, restart, next-file queue and legacy decoding")

    }
}
