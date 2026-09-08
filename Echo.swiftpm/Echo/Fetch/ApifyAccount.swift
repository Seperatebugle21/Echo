import Foundation

struct ApifyAccount: Identifiable, Codable, Hashable {

    let id: UUID
    var name: String
    var token: String

    init(
        id: UUID = UUID(),
        name: String,
        token: String
    ) {
        self.id = id
        self.name = name
        self.token = token
    }
}
