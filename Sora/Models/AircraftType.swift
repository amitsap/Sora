import Foundation
import SwiftData

@Model
final class AircraftType {
    var id: UUID
    var manufacturer: String
    var model: String
    var nickname: String?
    var firstFlownDate: Date?

    init(
        manufacturer: String,
        model: String,
        nickname: String? = nil,
        firstFlownDate: Date? = nil
    ) {
        self.id = UUID()
        self.manufacturer = manufacturer
        self.model = model
        self.nickname = nickname
        self.firstFlownDate = firstFlownDate
    }

    var fullName: String { "\(manufacturer) \(model)" }
    var displayName: String { nickname ?? fullName }
}
