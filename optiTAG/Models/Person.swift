import Foundation

struct Person: Identifiable, Equatable {
    let id: Int64
    var name: String
    var tag: String
    var note: String?
    var createdAt: Date
}
