import Foundation

@main struct PeopleChecks {
    static func rejects(_ action: () throws -> Void) {
        do { try action(); fatalError("Expected rejection") } catch {}
    }
    static func main() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = OptiTagDatabase(databaseURL: url)
        var first = [Float](repeating: 0, count: 512); first[0] = 1
        var second = [Float](repeating: 0, count: 512); second[1] = 1
        try db.enrollFace(name: "Alice", tag: "朋友", embedding: first)
        rejects { try db.enrollFace(name: " alice ", tag: "朋友", embedding: second) }
        rejects { try db.enrollFace(name: "Other", tag: "朋友", embedding: first) }
        precondition(tryCount(db) == 1)
        try db.enrollFace(name: "Bob", tag: "朋友", embedding: second)
        let people = try db.fetchPersons()
        let alice = people.first { $0.name == "Alice" }!.id
        let bob = people.first { $0.name == "Bob" }!.id
        rejects { try db.updatePerson(id: bob, name: "ALICE", tag: "朋友") }
        rejects { try db.addSample(personID: bob, embedding: first) }
        try db.addSample(personID: alice, embedding: first)
        var samples = try db.fetchFaceSamples()
        precondition(samples.filter { $0.personID == alice }.count == 2)
        try db.deleteSample(id: samples.first { $0.personID == alice }!.id)
        try db.insertRecognitionLog(personId: alice, recognizedName: "Alice", tag: "朋友")
        try db.deletePerson(id: alice)
        samples = try db.fetchFaceSamples()
        precondition(samples.allSatisfy { $0.personID != alice })
        let logs = try db.fetchRecentRecognitionLogs()
        precondition(logs[0].personId == nil && logs[0].name == "Alice")
        print("People contract checks passed: normalized uniqueness, face collisions, rollback, edit, samples, cascade and historical logs")
    }
    static func tryCount(_ db: OptiTagDatabase) -> Int { (try! db.fetchPersons()).count }
}
