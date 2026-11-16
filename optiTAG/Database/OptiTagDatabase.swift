import Foundation
import SQLite3

enum OptiTagDatabaseError: Error {
    case openDatabaseFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
}

final class OptiTagDatabase {
    static let shared = OptiTagDatabase()

    private var db: OpaquePointer?
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(databaseURL: URL? = nil) {
        do {
            try openDatabase(at: databaseURL)
            try createTables()

        } catch {
            assertionFailure("Database setup failed: \(error)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func fetchRecentRecognitionLogs(limit: Int = 20) throws -> [RecognitionLog] {
        let sql = """
        SELECT id, person_id, recognized_name, tag, confidence, recognized_at
        FROM recognition_logs
        ORDER BY recognized_at DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw OptiTagDatabaseError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var logs: [RecognitionLog] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let personId = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 1)
            let name = stringValue(statement, column: 2)
            let tag = stringValue(statement, column: 3)
            let confidence = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4)
            let recognizedAtText = stringValue(statement, column: 5)
            let recognizedAt = dateFormatter.date(from: recognizedAtText) ?? Date()

            logs.append(
                RecognitionLog(
                    id: id,
                    personId: personId,
                    name: name,
                    tag: tag,
                    confidence: confidence,
                    recognizedAt: recognizedAt
                )
            )
        }

        return logs
    }

    @discardableResult
    func insertPerson(name: String, tag: String, note: String? = nil) throws -> Int64 {
        try validateIdentity(name: name, tag: tag)
        let sql = """
        INSERT INTO persons (name, tag, note, created_at)
        VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw OptiTagDatabaseError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        bind(name, to: statement, index: 1)
        bind(tag, to: statement, index: 2)
        bind(note, to: statement, index: 3)
        bind(dateFormatter.string(from: Date()), to: statement, index: 4)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw OptiTagDatabaseError.executeFailed(errorMessage)
        }

        return sqlite3_last_insert_rowid(db)
    }

    @discardableResult
    func insertRecognitionLog(
        personId: Int64?,
        recognizedName: String,
        tag: String,
        confidence: Double? = nil,
        recognizedAt: Date = Date(),
        eventKey: String? = nil,
        sourceKey: String? = nil
    ) throws -> Int64 {
        let sql = """
        INSERT INTO recognition_logs (person_id, recognized_name, tag, confidence, recognized_at, event_key, source_key)
        VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(source_key) DO NOTHING;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw OptiTagDatabaseError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        if let personId {
            sqlite3_bind_int64(statement, 1, personId)
        } else {
            sqlite3_bind_null(statement, 1)
        }
        bind(recognizedName, to: statement, index: 2)
        bind(tag, to: statement, index: 3)
        if let confidence {
            sqlite3_bind_double(statement, 4, confidence)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        bind(dateFormatter.string(from: recognizedAt), to: statement, index: 5)
        if let eventKey { bind(eventKey, to: statement, index: 6) } else { sqlite3_bind_null(statement, 6) }
        if let sourceKey { bind(sourceKey, to: statement, index: 7) } else { sqlite3_bind_null(statement, 7) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw OptiTagDatabaseError.executeFailed(errorMessage)
        }

        return sqlite3_last_insert_rowid(db)
    }

    func deleteEventRecognitionLogs(eventKey: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM recognition_logs WHERE event_key=?;", -1, &statement, nil) == SQLITE_OK else { throw OptiTagDatabaseError.prepareFailed(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(eventKey, to: statement, index: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw OptiTagDatabaseError.executeFailed(errorMessage) }
    }

    private func openDatabase(at overrideURL: URL?) throws {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseURL = overrideURL ?? documentsURL.appendingPathComponent("optiTAG.sqlite")

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw OptiTagDatabaseError.openDatabaseFailed(errorMessage)
        }
    }

    struct FaceSample {
        let id: Int64
        let personID: Int64
        let name: String
        let tag: String
        let embedding: [Float]
    }

    func fetchFaceSamples() throws -> [FaceSample] {
        var statement: OpaquePointer?
        let sql = "SELECT p.id, p.name, p.tag, e.vector, e.id FROM face_embeddings e JOIN persons p ON p.id = e.person_id WHERE e.model = 'buffalo_s/w600k_mbf';"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw OptiTagDatabaseError.prepareFailed(errorMessage) }
        defer { sqlite3_finalize(statement) }
        var samples: [FaceSample] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            let text = stringValue(statement, column: 3)
            if let data = text.data(using: .utf8), let vector = try? JSONDecoder().decode([Float].self, from: data), vector.count == 512, vector.allSatisfy({ $0.isFinite }) {
                samples.append(FaceSample(id: sqlite3_column_int64(statement, 4), personID: sqlite3_column_int64(statement, 0), name: stringValue(statement, column: 1), tag: stringValue(statement, column: 2), embedding: vector))
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw OptiTagDatabaseError.executeFailed(errorMessage) }
        return samples
    }

    func enrollFace(name: String, tag: String, embedding: [Float]) throws {
        try validateIdentity(name: name, tag: tag)
        try validateFace(embedding)
        let vector = String(decoding: try JSONEncoder().encode(embedding), as: UTF8.self)
        try execute("BEGIN TRANSACTION;")
        do {
            let id = try insertPerson(name: name, tag: tag)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO face_embeddings (person_id, model, vector) VALUES (?, 'buffalo_s/w600k_mbf', ?);", -1, &statement, nil) == SQLITE_OK else { throw OptiTagDatabaseError.prepareFailed(errorMessage) }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            bind(vector, to: statement, index: 2)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw OptiTagDatabaseError.executeFailed(errorMessage) }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func fetchPersons() throws -> [Person] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id,name,tag,note,created_at FROM persons ORDER BY name,tag;", -1, &statement, nil) == SQLITE_OK else { throw OptiTagDatabaseError.prepareFailed(errorMessage) }
        defer { sqlite3_finalize(statement) }
        var people: [Person] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            people.append(Person(id: sqlite3_column_int64(statement, 0), name: stringValue(statement, column: 1), tag: stringValue(statement, column: 2), note: stringValue(statement, column: 3), createdAt: dateFormatter.date(from: stringValue(statement, column: 4)) ?? Date()))
        }
        return people
    }

    func validateIdentity(name: String, tag: String, excluding: Int64? = nil) throws {
        let key: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PersonError.message("請輸入姓名") }
        guard try !fetchPersons().contains(where: { $0.id != excluding && key($0.name) == key(name) && key($0.tag) == key(tag) }) else { throw PersonError.message("姓名與標籤的組合已存在") }
    }

    func updatePerson(id: Int64, name: String, tag: String) throws {
        try validateIdentity(name: name, tag: tag, excluding: id)
        try personStatement("UPDATE persons SET name=?,tag=? WHERE id=?;", id: id, values: [name, tag])
    }

    func deletePerson(id: Int64) throws {
        try personStatement("DELETE FROM persons WHERE id=?;", id: id)
    }

    func deleteSample(id: Int64) throws {
        try personStatement("DELETE FROM face_embeddings WHERE id=?;", id: id)
    }

    func addSample(personID: Int64, embedding: [Float]) throws {
        try validateFace(embedding, excluding: personID)
        let vector = String(decoding: try JSONEncoder().encode(embedding), as: UTF8.self)
        try personStatement("INSERT INTO face_embeddings (vector,person_id,model) VALUES (?,?,'buffalo_s/w600k_mbf');", id: personID, values: [vector])
    }

    private func personStatement(_ sql: String, id: Int64, values: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw OptiTagDatabaseError.prepareFailed(errorMessage) }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() { bind(value, to: statement, index: Int32(index + 1)) }
        sqlite3_bind_int64(statement, Int32(values.count + 1), id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw OptiTagDatabaseError.executeFailed(errorMessage) }
    }

    func validateFace(_ embedding: [Float], excluding: Int64? = nil) throws {
        guard embedding.count == 512, embedding.allSatisfy({ $0.isFinite }) else { throw PersonError.message("人臉特徵無效") }
        if let match = try fetchFaceSamples().first(where: { sample in
            sample.personID != excluding && zip(embedding, sample.embedding).reduce(Float(0)) { $0 + $1.0 * $1.1 } >= 0.45
        }) { throw PersonError.message("與「\(match.name)・\(match.tag)」過於相似，請改用編輯人物新增照片") }
    }

    private func createTables() throws {
        try execute("PRAGMA foreign_keys = ON;")
        try execute("""
        CREATE TABLE IF NOT EXISTS persons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            tag TEXT NOT NULL DEFAULT '未標記',
            note TEXT,
            created_at TEXT NOT NULL
        );
        """)

        try execute("""
        CREATE TRIGGER IF NOT EXISTS persons_identity_insert BEFORE INSERT ON persons
        WHEN EXISTS (SELECT 1 FROM persons WHERE lower(trim(name))=lower(trim(NEW.name)) AND lower(trim(tag))=lower(trim(NEW.tag)))
        BEGIN SELECT RAISE(ABORT, '姓名與標籤的組合已存在'); END;
        CREATE TRIGGER IF NOT EXISTS persons_identity_update BEFORE UPDATE OF name,tag ON persons
        WHEN EXISTS (SELECT 1 FROM persons WHERE id != NEW.id AND lower(trim(name))=lower(trim(NEW.name)) AND lower(trim(tag))=lower(trim(NEW.tag)))
        BEGIN SELECT RAISE(ABORT, '姓名與標籤的組合已存在'); END;
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS recognition_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id INTEGER,
            recognized_name TEXT NOT NULL,
            tag TEXT NOT NULL DEFAULT '未標記',
            confidence REAL,
            recognized_at TEXT NOT NULL,
            FOREIGN KEY (person_id) REFERENCES persons(id) ON DELETE SET NULL
        );
        """)
        var columns = Set<String>()
        var info: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(recognition_logs);", -1, &info, nil) == SQLITE_OK else { throw OptiTagDatabaseError.prepareFailed(errorMessage) }
        while sqlite3_step(info) == SQLITE_ROW { columns.insert(stringValue(info, column: 1)) }
        sqlite3_finalize(info)
        if !columns.contains("event_key") { try execute("ALTER TABLE recognition_logs ADD COLUMN event_key TEXT;") }
        if !columns.contains("source_key") { try execute("ALTER TABLE recognition_logs ADD COLUMN source_key TEXT;") }
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS recognition_source ON recognition_logs(source_key);")
        try execute("CREATE INDEX IF NOT EXISTS recognition_event ON recognition_logs(event_key);")
        try execute("""
        CREATE TABLE IF NOT EXISTS face_embeddings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
            model TEXT NOT NULL,
            vector TEXT NOT NULL
        );
        """)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw OptiTagDatabaseError.executeFailed(errorMessage)
        }
    }

    private func bind(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func stringValue(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let text = sqlite3_column_text(statement, column) else {
            return ""
        }
        return String(cString: text)
    }

    private var errorMessage: String {
        guard let db else {
            return "Database is not open"
        }
        return String(cString: sqlite3_errmsg(db))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum PersonError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
