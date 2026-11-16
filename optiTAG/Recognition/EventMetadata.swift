import Foundation

enum EventMetadata {
    static func validateFaces(_ rows: [[String: String]]) throws {
        var requests: [String: String] = [:], images = Set<String>(), indices = Set<String>(), sentinels = Set<String>()
        for row in rows {
            guard let id = row["event_id"], id.utf8.count == 16, let value = UInt64(id, radix: 16), value != 0,
                  let request = row["request_id"].flatMap(UInt32.init),
                  let image = row["image_id"].flatMap(UInt32.init),
                  let index = row["face_index"].flatMap(Int.init),
                  let count = row["face_count"].flatMap(UInt16.init) else { throw PersonError.message("人臉 metadata 欄位無效") }
            let scope = String(id.prefix(8)) + ":"
            let batch = id + ":" + String(request)
            if request != 0 {
                let key = scope + String(request)
                if let owner = requests[key], owner != id { throw PersonError.message("request ID 跨 event 衝突") }
                requests[key] = id
            }
            if image == 0 && index == -1 {
                guard ["COMPLETED", "NO_FACE", "PARTIAL", "BUSY", "TIMEOUT", "DISCONNECTED", "FAILED"].contains(row["status"] ?? ""),
                      request == 0 || sentinels.insert(batch).inserted else { throw PersonError.message("人臉 batch 終態重複或無效") }
                if row["status"] == "NO_FACE", count != 0 { throw PersonError.message("NO_FACE 數量不符") }
            } else {
                guard request != 0, image != 0, index >= 0, index < Int(count),
                      ["RECOGNIZED", "UNKNOWN", "CLIENT_NO_FACE", "FAILED"].contains(row["status"] ?? ""),
                      images.insert(scope + String(image)).inserted,
                      indices.insert(batch + ":" + String(index)).inserted else { throw PersonError.message("人臉 image/index ownership 重複或無效") }
            }
        }
        // Missing terminals prevent import rather than allowing destructive cleanup.
        for row in rows where row["image_id"] != "0" {
            guard sentinels.contains((row["event_id"] ?? "") + ":" + (row["request_id"] ?? "")) else { throw PersonError.message("人臉 batch 缺少終態") }
        }
    }
}
