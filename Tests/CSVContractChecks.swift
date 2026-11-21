import Foundation

enum PersonError: Error { case message(String) }

@main struct Checks {
    static func main() throws {
        let rows = try EventCSV.rows("event_id,person_id\n0000002500000068,\"P,\"\"01\nnext\"\n")
        precondition(rows[0]["person_id"] == "P,\"01\nnext")
        precondition(rows[0]["event_id"] == "0000002500000068")
        let bom = try EventCSV.rows("\u{FEFF}a,b\r\n1,2\r\n")
        precondition(bom[0]["a"] == "1")
        for bad in ["a,a\n1,2\n", "a,b\n1\n", "a,b\n\"oops,2", "a,b\n\"ok\"junk,2\n"] {
            do { _ = try EventCSV.rows(bad); fatalError("Accepted invalid CSV") } catch {}
        }
        print("CSV contract checks passed: quoted commas, escaped quotes, embedded newlines, BOM/CRLF, IDs, malformed input")
    }
}
