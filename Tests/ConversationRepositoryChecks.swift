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
        // Cleanup is isolated by device and persists partial acknowledgements.
        var other = silent
        other = ConversationEvent(deviceID: "other-device", eventID: silent.eventID, firstSample: 0, vadStartSample: 0, vadStartUs: 0, endUs: 1, audioPath: silent.audioPath)
        other.localAudioDeleted = true
        try repository.save(events: [other], summaries: [])
        let sameDevice = try repository.cleanup(deviceID: "test-device")
        precondition(sameDevice.allSatisfy { $0.deviceID == "test-device" })
        silent.deviceAudioDeleted = true
        try repository.save(events: [silent], summaries: [])
        let afterPartial = try ConversationRepository(url: url).cleanup(deviceID: "test-device")
        precondition(!afterPartial.contains { $0.id == silent.id })
        precondition(afterPartial.contains { $0.id == event.id })
        let otherPending = try repository.cleanup(deviceID: "other-device")
        precondition(otherPending.count == 1 && !otherPending[0].deviceAudioDeleted)
        // A single cleanup round drains multiple database pages with durable per-file progress.
        var many: [ConversationEvent] = []
        for number in 1...205 {
            let id = String(format: "%016llX", UInt64(number))
            var item = ConversationEvent(deviceID: "batch-device", eventID: id, firstSample: 0, vadStartSample: 0, vadStartUs: 0, endUs: 1, audioPath: "event_" + id + ".wav")
            item.localAudioDeleted = true
            many.append(item)
        }
        try repository.save(events: many, summaries: [])
        let total = try repository.cleanupCount(deviceID: "batch-device")
        precondition(total == 205)
        var pages: [Int] = [], completed = 0
        while true {
            let page = try repository.cleanup(deviceID: "batch-device")
            if page.isEmpty { break }
            pages.append(page.count)
            for var item in page {
                item.deviceAudioDeleted = true
                try repository.save(events: [item], summaries: [])
                completed += 1
                let remaining = try repository.cleanupCount(deviceID: "batch-device")
                precondition(remaining == total - completed)
            }
        }
        precondition(pages == [100, 100, 5] && completed == 205)
        let afterRestart = try ConversationRepository(url: url).cleanupCount(deviceID: "batch-device")
        precondition(afterRestart == 0)
        // No count or silence-gap boundary: 205 short events fit in one request.
        let prompt = "測試提示"
        var work: [SummaryWork] = []
        for number in 0..<205 {
            var item = event
            item = ConversationEvent(deviceID: "large-queue", eventID: String(format: "%016X", number + 1), firstSample: 0, vadStartSample: 0, vadStartUs: Int64(number) * 200_000_000, endUs: Int64(number) * 200_000_000 + 1000, audioPath: "test.wav")
            item.segments = [TranscriptSegment(start: 0, end: 1, text: "測試對話")]
            try repository.save(events: [item], summaries: [])
            work += try SummaryBatching.fragments(item, prompt: prompt)
        }
        let packed = try SummaryBatching.batches(work, prompt: prompt)
        precondition(packed.count == 1 && packed[0].count == 205)
        var loaded: [ConversationEvent] = [], cursor = ""
        while true {
            let page = try repository.eventPage(after: cursor)
            guard let last = page.last else { break }
            loaded += page; cursor = last.id
        }
        precondition(loaded.filter { $0.deviceID == "large-queue" }.count == 205)
        var huge = event
        huge = ConversationEvent(deviceID: "huge", eventID: "0000000100000001", firstSample: 0, vadStartSample: 0, vadStartUs: 0, endUs: 1, audioPath: "huge.wav")
        let original = String(repeating: "超長逐字稿測試", count: 20000)
        huge.segments = [TranscriptSegment(start: 0, end: 100, text: original)]
        try repository.save(events: [huge], summaries: [])
        let fragments = try repository.summaryPlan(huge, prompt: prompt)
        precondition(fragments.count > 1)
        precondition(fragments.flatMap { $0.event.segments }.map(\.text).joined() == original)
        for fragment in fragments { let bytes = try SummaryBatching.size([fragment.event], prompt: prompt); precondition(bytes <= SummaryBatching.byteLimit) }
        var altered = huge; altered.segments = []
        let frozen = try repository.summaryPlan(altered, prompt: prompt)
        precondition(frozen.map(\.key) == fragments.map(\.key))
        let face = ["request_id": "1", "image_id": "2", "face_index": "0", "face_count": "1", "person_id": "9", "name": "小明", "status": "RECOGNIZED"]
        try repository.saveFace(eventID: huge.id, row: face)
        try repository.saveFace(eventID: huge.id, row: face)
        let faceRows = try repository.faces(eventID: huge.id); precondition(faceRows.count == 1)
        var conflict = face; conflict["person_id"] = "10"
        do { try repository.saveFace(eventID: huge.id, row: conflict); fatalError("Expected ownership conflict") } catch {}
        var firstSummary = ConversationSummary(id: "part1", sourceIDs: [huge.id], createdAt: Date(), title: "第一段", overview: "摘要", decisions: [], tasks: [], questions: [])
        firstSummary.sourceSnapshots = [fragments[0].event]; firstSummary.workKeys = [fragments[0].key]
        var secondSummary = firstSummary; secondSummary = ConversationSummary(id: "part2", sourceIDs: [huge.id], createdAt: Date(), title: "第二段", overview: "摘要", decisions: [], tasks: [], questions: [], sourceSnapshots: [fragments[1].event], workKeys: [fragments[1].key])
        try repository.save(events: [], summaries: [firstSummary, secondSummary])
        let checkpoint = try repository.hasWork(fragments[0].key); precondition(checkpoint)
        let incomplete = try repository.hasSummary(eventID: huge.id); precondition(!incomplete)
        try repository.deleteSummary("part1")
        let remainingWork = try repository.summaryPlan(huge, prompt: prompt)
        precondition(remainingWork.count == fragments.count - 2)
        let partiallyDeleted = try repository.event(id: huge.id)!
        precondition(partiallyDeleted.segments.map(\.text).joined() == fragments.dropFirst(2).flatMap { $0.event.segments }.map(\.text).joined())
        try repository.markFinished(huge.id) // Simulate completion of remaining work before the final deletion.
        let retained = try repository.sources(summaryID: "part2")
        precondition(retained.count == 1 && !retained[0].segments.isEmpty)
        try repository.deleteSummary("part2")
        let deleted = try repository.event(id: huge.id)!
        precondition(deleted.contentDeleted == true && deleted.segments.isEmpty)
        try repository.saveFace(eventID: huge.id, row: face)
        let removedFaces = try repository.faces(eventID: huge.id); precondition(removedFaces.isEmpty)
        let tombstone = try ConversationRepository(url: url).hasSummary(eventID: huge.id); precondition(tombstone)
        print("Event summary checks passed: 205-event batching, byte budget, lossless splitting, frozen plans, face conflicts, checkpoints, shared sources and deletion tombstones")
        print("Conversation checks passed: persistence, search, rollback, no-speech cleanup, restart, next-file queue and legacy decoding")

    }
}
