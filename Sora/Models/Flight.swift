import Foundation
import SwiftData

@Model
final class Flight {
    var id: UUID
    var flightNumber: String
    var airline: String

    // Aircraft
    var aircraftType: String
    var aircraftRegistration: String?

    // Airports — stored as Codable structs (SwiftData serializes these automatically)
    var departureAirport: Airport
    var arrivalAirport: Airport

    // Times
    var departureDate: Date
    var arrivalDate: Date

    // Distance
    var distanceMiles: Double

    // Cabin — raw string backing so SwiftData can persist it
    var cabinClassRawValue: String
    var seatNumber: String?

    // Notes
    var notes: String?

    // Photos — PHAsset identifiers only, never copy image data
    var photoAssetIdentifiers: [String]

    var isCompleted: Bool

    init(
        flightNumber: String,
        airline: String,
        aircraftType: String,
        aircraftRegistration: String? = nil,
        departureAirport: Airport,
        arrivalAirport: Airport,
        departureDate: Date,
        arrivalDate: Date,
        distanceMiles: Double,
        cabinClass: CabinClass = .economy,
        seatNumber: String? = nil,
        notes: String? = nil,
        photoAssetIdentifiers: [String] = [],
        isCompleted: Bool = true
    ) {
        self.id = UUID()
        self.flightNumber = flightNumber
        self.airline = airline
        self.aircraftType = aircraftType
        self.aircraftRegistration = aircraftRegistration
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.distanceMiles = distanceMiles
        self.cabinClassRawValue = cabinClass.rawValue
        self.seatNumber = seatNumber
        self.notes = notes
        self.photoAssetIdentifiers = photoAssetIdentifiers
        self.isCompleted = isCompleted
    }

    // Type-safe cabin class accessor
    var cabinClass: CabinClass {
        get { CabinClass(rawValue: cabinClassRawValue) ?? .economy }
        set { cabinClassRawValue = newValue.rawValue }
    }

    // Duration is always derived from stored dates
    var duration: TimeInterval {
        max(0, arrivalDate.timeIntervalSince(departureDate))
    }

    var durationFormatted: String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    var distanceFormatted: String {
        DistanceUnit.current.format(fromMiles: distanceMiles)
    }

    var routeString: String {
        "\(departureAirport.iataCode) → \(arrivalAirport.iataCode)"
    }

    var isUpcoming: Bool {
        departureDate > Date()
    }

    // Formatted flight number with padding for monospace display
    var formattedFlightNumber: String {
        flightNumber.uppercased()
    }
}
