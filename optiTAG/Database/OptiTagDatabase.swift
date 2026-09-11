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

    private init() {
        do {
            try openDatabase()
            try createTables()
            try seedInitialDataIfNeeded()
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
        recognizedAt: Date = Date()
    ) throws -> Int64 {
        let sql = """
        INSERT INTO recognition_logs (person_id, recognized_name, tag, confidence, recognized_at)
        VALUES (?, ?, ?, ?, ?);
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

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw OptiTagDatabaseError.executeFailed(errorMessage)
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func openDatabase() throws {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseURL = documentsURL.appendingPathComponent("optiTAG.sqlite")

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw OptiTagDatabaseError.openDatabaseFailed(errorMessage)
        }
    }

    private func createTables() throws {
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
    }

    private func seedInitialDataIfNeeded() throws {
        guard try recognitionLogCount() == 0 else {
            return
        }

        let now = Date()
        let ming = try insertPerson(name: "王小明", tag: "同學")
        let li = try insertPerson(name: "李華", tag: "教授")
        let chen = try insertPerson(name: "陳志強", tag: "朋友")

        try insertRecognitionLog(personId: ming, recognizedName: "王小明", tag: "同學", confidence: 0.93, recognizedAt: now.addingTimeInterval(-120))
        try insertRecognitionLog(personId: li, recognizedName: "李華", tag: "教授", confidence: 0.89, recognizedAt: now.addingTimeInterval(-900))
        try insertRecognitionLog(personId: chen, recognizedName: "陳志強", tag: "朋友", confidence: 0.86, recognizedAt: now.addingTimeInterval(-3600))
        try insertRecognitionLog(personId: nil, recognizedName: "未知人物", tag: "未標記", confidence: nil, recognizedAt: now.addingTimeInterval(-7200))
    }

    private func recognitionLogCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM recognition_logs;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw OptiTagDatabaseError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
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
