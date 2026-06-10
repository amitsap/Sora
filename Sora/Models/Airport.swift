import Foundation
import CoreLocation

struct Airport: Codable, Hashable, Identifiable, Equatable, Sendable {
    var id: String { iataCode }

    var iataCode: String
    var icaoCode: String
    var name: String
    var city: String
    var country: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayName: String { "\(city) (\(iataCode))" }
    var fullDisplayName: String { "\(name), \(city)" }

    // Placeholder for when airport data is being entered manually
    static func placeholder(iata: String) -> Airport {
        Airport(
            iataCode: iata.uppercased(),
            icaoCode: "",
            name: iata.uppercased(),
            city: iata.uppercased(),
            country: "",
            latitude: 0,
            longitude: 0
        )
    }
}
