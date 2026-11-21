import Foundation
import SQLite3

/// Indexed durable records; the UI loads pages and the worker loads bounded queues.
final class ConversationRepository {
    private var db: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw PersonError.message("無法開啟對話資料庫") }
        try execute("""
        PRAGMA foreign_keys=ON;
        CREATE TABLE IF NOT EXISTS conversation_events (
          id TEXT PRIMARY KEY, device TEXT NOT NULL, boot TEXT NOT NULL,
          local_deleted INTEGER NOT NULL, device_deleted INTEGER NOT NULL, body BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS conversation_cleanup ON conversation_events(device,local_deleted,device_deleted);
        CREATE TABLE IF NOT EXISTS conversation_summaries (
          id TEXT PRIMARY KEY, created REAL NOT NULL, search_text TEXT NOT NULL, body BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS conversation_recent ON conversation_summaries(created DESC);
        CREATE TABLE IF NOT EXISTS conversation_sources (
          event_id TEXT PRIMARY KEY REFERENCES conversation_events(id),
          summary_id TEXT NOT NULL REFERENCES conversation_summaries(id));
        """)
        // Rebuild the old one-summary-per-event join without losing existing links.
        try execute("""
        BEGIN IMMEDIATE;
        CREATE TABLE IF NOT EXISTS conversation_links (
          event_id TEXT NOT NULL REFERENCES conversation_events(id),
          summary_id TEXT NOT NULL REFERENCES conversation_summaries(id), PRIMARY KEY(event_id,summary_id));
        INSERT OR IGNORE INTO conversation_links SELECT event_id,summary_id FROM conversation_sources;
        CREATE TABLE IF NOT EXISTS conversation_done (event_id TEXT PRIMARY KEY);
        INSERT OR IGNORE INTO conversation_done SELECT event_id FROM conversation_sources;
        DROP TABLE conversation_sources;
        CREATE TABLE conversation_sources (event_id TEXT PRIMARY KEY, summary_id TEXT);
        CREATE TABLE IF NOT EXISTS conversation_work (work_key TEXT PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS conversation_plans (event_id TEXT PRIMARY KEY, body BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS event_faces (face_key TEXT PRIMARY KEY, event_id TEXT NOT NULL, body BLOB NOT NULL);
        COMMIT;
        """)
    }
    deinit { sqlite3_close(db) }

    func save(events: [ConversationEvent], summaries: [ConversationSummary]) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            for event in events {
                try statement("INSERT INTO conversation_events(id,device,boot,local_deleted,device_deleted,body) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET local_deleted=excluded.local_deleted,device_deleted=excluded.device_deleted,body=excluded.body;", values: [event.id, event.deviceID, event.boot, event.localAudioDeleted ? "1" : "0", event.deviceAudioDeleted ? "1" : "0"], data: JSONEncoder().encode(event))
            }
            for summary in summaries {
                let search = ([summary.title, summary.overview] + summary.decisions + summary.tasks + summary.questions).joined(separator: " ")
                try statement("INSERT INTO conversation_summaries(id,created,search_text,body) VALUES(?,?,?,?) ON CONFLICT(id) DO NOTHING;", values: [summary.id, String(summary.createdAt.timeIntervalSince1970), search], data: JSONEncoder().encode(summary))
                for source in summary.sourceIDs {
                    try statement("INSERT INTO conversation_links(event_id,summary_id) VALUES(?,?) ON CONFLICT(event_id,summary_id) DO NOTHING;", values: [source, summary.id])
                }
                for key in summary.workKeys ?? [] {
                    try statement("INSERT OR IGNORE INTO conversation_work(work_key) VALUES(?);", values: [key])
                }
                if summary.workKeys == nil {
                    for source in summary.sourceIDs { try markFinished(source) }
                }
            }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }
    func event(id: String) throws -> ConversationEvent? {
        let rows: [ConversationEvent] = try query("SELECT body FROM conversation_events WHERE id=?;", values: [id])
        return rows.first
    }
    func recentEvents() throws -> [ConversationEvent] {
        try query("SELECT body FROM conversation_events ORDER BY id DESC LIMIT 100;")
    }
    func unfinished() throws -> [ConversationEvent] {
        try query("SELECT e.body FROM conversation_events e WHERE e.local_deleted=0 ORDER BY e.id LIMIT 100;")
    }
    private func exists(_ sql: String, _ value: String) throws -> Bool {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK else { throw failure }
        defer { sqlite3_finalize(result) }
        bind(value, statement: result, index: 1)
        let step = sqlite3_step(result)
        guard step == SQLITE_ROW || step == SQLITE_DONE else { throw failure }
        return step == SQLITE_ROW
    }
    func hasSummary(eventID: String) throws -> Bool {
        try exists("SELECT 1 FROM conversation_done WHERE event_id=?;", eventID)
    }
    func summaryPlan(_ event: ConversationEvent, prompt: String) throws -> [SummaryWork] {
        let existing: [[SummaryWork]] = try query("SELECT body FROM conversation_plans WHERE event_id=?;", values: [event.id])
        if let plan = existing.first { return plan }
        let plan = try SummaryBatching.fragments(event, prompt: prompt)
        try statement("INSERT INTO conversation_plans(event_id,body) VALUES(?,?);", values: [event.id], data: JSONEncoder().encode(plan))
        return plan
    }
    func hasWork(_ key: String) throws -> Bool {
        try exists("SELECT 1 FROM conversation_work WHERE work_key=?;", key)
    }
    func markFinished(_ id: String) throws {
        try statement("INSERT OR IGNORE INTO conversation_done(event_id) VALUES(?);", values: [id])
        try statement("DELETE FROM conversation_plans WHERE event_id=?;", values: [id])
    }
    func eventPage(after cursor: String = "") throws -> [ConversationEvent] {
        try query("SELECT body FROM conversation_events WHERE id>? ORDER BY id LIMIT 100;", values: [cursor])
    }
    func saveFace(eventID: String, row: [String: String]) throws {
        if try event(id: eventID)?.contentDeleted == true { return }
        let key = eventID + ":" + (row["request_id"] ?? "") + ":" + (row["image_id"] ?? "")
        let old: [[String: String]] = try query("SELECT body FROM event_faces WHERE face_key=?;", values: [key])
        if let previous = old.first {
            for field in ["person_id", "status", "face_index", "face_count"] where previous[field] != row[field] {
                throw PersonError.message("人臉來源資料衝突：\(field)")
            }
            return
        }
        try statement("INSERT INTO event_faces(face_key,event_id,body) VALUES(?,?,?);", values: [key,eventID], data: JSONEncoder().encode(row))
    }
    func faces(eventID: String) throws -> [[String: String]] {
        try query("SELECT body FROM event_faces WHERE event_id=? ORDER BY face_key;", values: [eventID])
    }
    func deleteSummary(_ id: String) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            let sources = try sources(summaryID: id)
            try statement("DELETE FROM conversation_links WHERE summary_id=?;", values: [id])
            try statement("DELETE FROM conversation_summaries WHERE id=?;", values: [id])
            for source in sources {
                if var event = try event(id: source.id) {
                    let savedPlans: [[SummaryWork]] = try query("SELECT body FROM conversation_plans WHERE event_id=?;", values: [event.id])
                    let pending = try (savedPlans.first ?? []).filter { try !hasWork($0.key) }
                    if pending.isEmpty {
                        event.segments = []; event.faceAssociations = []; event.lifecycle = []; event.contentDeleted = true
                        try statement("DELETE FROM event_faces WHERE event_id=?;", values: [event.id])
                        try markFinished(event.id)
                    } else {
                        // Remove deleted/completed text, retaining only work that has never been summarized.
                        event.segments = pending.flatMap { $0.event.segments }
                        try statement("UPDATE conversation_plans SET body=?2 WHERE event_id=?1;", values: [event.id], data: JSONEncoder().encode(pending))
                    }
                    try statement("UPDATE conversation_events SET body=?2 WHERE id=?1;", values: [event.id], data: JSONEncoder().encode(event))
                }
            }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }
    func cleanup(deviceID: String, after cursor: String = "") throws -> [ConversationEvent] {
        try query("SELECT body FROM conversation_events WHERE device=? AND local_deleted=1 AND device_deleted=0 AND id>? ORDER BY id LIMIT 100;", values: [deviceID, cursor])
    }
    func cleanupCount(deviceID: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM conversation_events WHERE device=? AND local_deleted=1 AND device_deleted=0;", -1, &statement, nil) == SQLITE_OK else { throw failure }
        defer { sqlite3_finalize(statement) }
        bind(deviceID, statement: statement, index: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw failure }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func sources(summaryID: String) throws -> [ConversationEvent] {
        let summaries: [ConversationSummary] = try query("SELECT body FROM conversation_summaries WHERE id=?;", values: [summaryID])
        if let snapshots = summaries.first?.sourceSnapshots { return snapshots }
        return try query("SELECT e.body FROM conversation_events e JOIN conversation_links s ON s.event_id=e.id WHERE s.summary_id=? ORDER BY e.id;", values: [summaryID])
    }
    func summaries(search: String = "", limit: Int = 100) throws -> [ConversationSummary] {
        // instr treats user input literally (no SQL wildcard interpretation).
        try query("SELECT body FROM conversation_summaries WHERE ?='' OR instr(lower(search_text),lower(?))>0 ORDER BY created DESC LIMIT ?;", values: [search, search, String(limit)])
    }
    private func query<T: Decodable>(_ sql: String, values: [String] = []) throws -> [T] {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK else { throw failure }
        defer { sqlite3_finalize(result) }
        for (index, value) in values.enumerated() { bind(value, statement: result, index: Int32(index + 1)) }
        var output: [T] = []
        var step = sqlite3_step(result)
        while step == SQLITE_ROW {
            let size = Int(sqlite3_column_bytes(result, 0))
            guard let bytes = sqlite3_column_blob(result, 0) else { throw failure }
            output.append(try JSONDecoder().decode(T.self, from: Data(bytes: bytes, count: size)))
            step = sqlite3_step(result)
        }
        guard step == SQLITE_DONE else { throw failure }
        return output
    }
    private func statement(_ sql: String, values: [String], data: Data? = nil) throws {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK else { throw failure }
        defer { sqlite3_finalize(result) }
        for (index, value) in values.enumerated() { bind(value, statement: result, index: Int32(index + 1)) }
        if let data {
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(result, Int32(values.count + 1), bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
        guard sqlite3_step(result) == SQLITE_DONE else { throw failure }
    }
    private func bind(_ value: String, statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure }
    }
    private var failure: Error { PersonError.message(db.map { String(cString: sqlite3_errmsg($0)) } ?? "對話資料庫未開啟") }
}
