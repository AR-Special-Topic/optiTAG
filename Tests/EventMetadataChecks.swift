import Foundation

enum PersonError: Error { case message(String) }

@main struct MetadataChecks {
    static func main() throws {
        let id = "0000002500000068"
        func face(_ event: String, _ request: String, _ image: String, _ index: String = "0") -> [String:String] {
            ["event_id": event, "request_id": request, "image_id": image, "face_index": index, "face_count": "1", "status": image == "0" ? "COMPLETED" : "RECOGNIZED"]
        }
        let first = face(id, "1", "1")
        let sentinel = face(id, "1", "0", "-1")
        let second = face(id, "2", "2") // A later batch restarts face_index at zero.
        let secondEnd = face(id, "2", "0", "-1")
        try EventMetadata.validateFaces([first, sentinel, second, secondEnd])
        for bad in [[first], [first, first, sentinel], [sentinel, sentinel], [first, sentinel, face("0000002500000069", "1", "3")]] {
            do { try EventMetadata.validateFaces(bad); fatalError("Expected metadata rejection") } catch {}
        }
        print("Event metadata checks passed: multiple batches, sentinel rows, missing terminals, duplicate faces and request ownership")
    }
}
