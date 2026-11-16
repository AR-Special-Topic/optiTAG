import Foundation

/// CSV with quoted commas, escaped quotes and embedded newlines.
enum EventCSV {
    static func rows(_ source: String) throws -> [[String: String]] {
        var text = source.replacingOccurrences(of: "\r\n", with: "\n")
        if text.first == "\u{FEFF}" { text.removeFirst() }
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false
        var iterator = text.makeIterator()
        var current = iterator.next()
        while let char = current {
            if quoted {
                if char == "\"" {
                    let next = iterator.next()
                    if next == "\"" { field.append("\""); current = iterator.next(); continue }
                    quoted = false; closed = true; current = next; continue
                }
                field.append(char)
            } else if char == "," {
                row.append(field); field = ""; closed = false
            } else if char == "\n" {
                row.append(field); rows.append(row); row = []; field = ""; closed = false
            } else if char == "\"", field.isEmpty, !closed {
                quoted = true
            } else {
                guard !closed, char != "\"" else { throw PersonError.message("CSV 引號位置錯誤") }
                field.append(char)
            }
            current = iterator.next()
        }
        guard !quoted else { throw PersonError.message("CSV 引號未結束") }
        if !field.isEmpty || !row.isEmpty || closed { row.append(field); rows.append(row) }
        guard let header = rows.first, !header.contains(""), Set(header).count == header.count else { throw PersonError.message("CSV header 無效") }
        return try rows.dropFirst().filter { $0 != [""] }.map { values in
            guard values.count == header.count else { throw PersonError.message("CSV 欄位數不符") }
            return Dictionary(uniqueKeysWithValues: zip(header, values))
        }
    }
}
