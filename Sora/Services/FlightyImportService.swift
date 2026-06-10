import Foundation
import SwiftData

// MARK: - Result

struct FlightyImportResult {
    let imported: Int
    let skipped: Int          // canceled / diverted / unparseable rows
    let unknownAirports: [String]  // IATA codes not in the bundled DB
}

// MARK: - Service

enum FlightyImportService {

    // Column names from Flighty CSV export
    private enum Col {
        static let date           = "Date"
        static let airline        = "Airline"
        static let flight         = "Flight"
        static let from           = "From"
        static let to             = "To"
        static let canceled       = "Canceled"
        static let divertedTo     = "Diverted To"
        static let depActual      = "Gate Departure (Actual)"
        static let depScheduled   = "Gate Departure (Scheduled)"
        static let takeoffActual  = "Take off (Actual)"
        static let takeoffScheduled = "Take off (Scheduled)"
        static let landingActual  = "Landing (Actual)"
        static let landingScheduled = "Landing (Scheduled)"
        static let arrActual      = "Gate Arrival (Actual)"
        static let arrScheduled   = "Gate Arrival (Scheduled)"
        static let aircraftType   = "Aircraft Type Name"
        static let tailNumber     = "Tail Number"
        static let seat           = "Seat"
        static let cabinClass     = "Cabin Class"
        static let notes          = "Notes"
    }

    static func importCSV(url: URL, into context: ModelContext) throws -> FlightyImportResult {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return try importCSV(contents: raw, into: context)
    }

    static func importCSV(contents raw: String, into context: ModelContext) throws -> FlightyImportResult {
        let rows = parseCSV(raw)
        guard let header = rows.first else {
            return FlightyImportResult(imported: 0, skipped: 0, unknownAirports: [])
        }

        // Build column index
        let idx = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces), $0) })

        var imported = 0
        var skipped = 0
        var unknownAirports = Set<String>()

        for row in rows.dropFirst() {
            guard row.count == header.count else { skipped += 1; continue }

            func field(_ name: String) -> String {
                guard let i = idx[name], i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespaces)
            }

            // Skip canceled flights
            let canceled = field(Col.canceled).lowercased()
            let divertedTo = field(Col.divertedTo)
            if canceled == "true" || canceled == "yes" || canceled == "1" || !divertedTo.isEmpty {
                skipped += 1
                continue
            }

            let flightNumber = field(Col.flight)
            let fromIATA     = normalizedAirportCode(from: field(Col.from))
            let toIATA       = normalizedAirportCode(from: field(Col.to))
            let dateStr      = field(Col.date)

            guard !flightNumber.isEmpty, !fromIATA.isEmpty, !toIATA.isEmpty, !dateStr.isEmpty else {
                skipped += 1; continue
            }

            // Airports — prefer bundled DB, fall back to placeholder
            let depAirport: Airport
            let arrAirport: Airport
            if let a = AirportDatabase.lookup(fromIATA) {
                depAirport = a
            } else {
                depAirport = Airport.placeholder(iata: fromIATA)
                unknownAirports.insert(fromIATA)
            }
            if let a = AirportDatabase.lookup(toIATA) {
                arrAirport = a
            } else {
                arrAirport = Airport.placeholder(iata: toIATA)
                unknownAirports.insert(toIATA)
            }

            // Times — prefer actual, fall back to scheduled
            let depTimeStr = preferredField(
                field(Col.takeoffActual),
                field(Col.depActual),
                field(Col.takeoffScheduled),
                field(Col.depScheduled)
            )
            let arrTimeStr = preferredField(
                field(Col.landingActual),
                field(Col.arrActual),
                field(Col.landingScheduled),
                field(Col.arrScheduled)
            )

            guard let depDate = parseDateTime(date: dateStr, time: depTimeStr) ?? parseDate(dateStr) else {
                skipped += 1
                continue
            }

            let distance = haversineDistance(from: depAirport.coordinate, to: arrAirport.coordinate)
            let parsedArrival = parseDateTime(date: dateStr, time: arrTimeStr)
            let arrDate = resolvedArrivalDate(
                departureDate: depDate,
                parsedArrivalDate: parsedArrival,
                departureAirport: depAirport,
                arrivalAirport: arrAirport,
                distanceMiles: distance
            )
            let cabin    = parseCabinClass(field(Col.cabinClass))

            let flight = Flight(
                flightNumber: flightNumber.uppercased(),
                airline:      field(Col.airline),
                aircraftType: field(Col.aircraftType),
                aircraftRegistration: nilIfEmpty(field(Col.tailNumber)),
                departureAirport: depAirport,
                arrivalAirport:   arrAirport,
                departureDate:    depDate,
                arrivalDate:      arrDate,
                distanceMiles:    distance,
                cabinClass:       cabin,
                seatNumber:       nilIfEmpty(field(Col.seat)),
                notes:            nilIfEmpty(field(Col.notes)),
                isCompleted:      true
            )
            context.insert(flight)
            imported += 1
        }

        return FlightyImportResult(
            imported: imported,
            skipped: skipped,
            unknownAirports: unknownAirports.sorted()
        )
    }

    // MARK: - CSV parsing (handles quoted fields with commas)

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        // Escaped quote
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    current.append(field)
                    field = ""
                case "\r\n", "\n", "\r":
                    current.append(field)
                    field = ""
                    if !current.isEmpty {
                        rows.append(current)
                        current = []
                    }
                default:
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }

        // Last field / row
        current.append(field)
        if current.contains(where: { !$0.isEmpty }) {
            rows.append(current)
        }

        return rows
    }

    // MARK: - Date / time parsing

    // Flighty exports a mix of full datetimes and time-only values.
    private static let dateTimeFormatters: [DateFormatter] = {
        let fmts = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd h:mm a",
            "yyyy-MM-dd h:mm:ss a",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mmZ",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy h:mm a",
            "MM/dd/yyyy h:mm:ss a",
            "dd/MM/yyyy HH:mm",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy h:mm a",
            "dd/MM/yyyy h:mm:ss a",
        ]
        return fmts.map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    private static let timeOnlyFormatters: [DateFormatter] = {
        let fmts = [
            "HH:mm:ss",
            "HH:mm",
            "h:mm a",
            "h:mm:ss a",
            "h a"
        ]
        return fmts.map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    private static let dateOnlyFormatters: [DateFormatter] = {
        let fmts = ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy"]
        return fmts.map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    private static func parseDateTime(date: String, time: String) -> Date? {
        guard !time.isEmpty else { return nil }

        let trimmedDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTime = time.trimmingCharacters(in: .whitespacesAndNewlines)

        for f in dateTimeFormatters {
            if let d = f.date(from: trimmedTime) { return d }
        }

        if let baseDate = parseDate(trimmedDate) {
            let calendar = Calendar.current
            for formatter in timeOnlyFormatters {
                if let parsedTime = formatter.date(from: trimmedTime) {
                    let components = calendar.dateComponents([.hour, .minute, .second], from: parsedTime)
                    if let combined = calendar.date(
                        bySettingHour: components.hour ?? 0,
                        minute: components.minute ?? 0,
                        second: components.second ?? 0,
                        of: baseDate
                    ) {
                        return combined
                    }
                }
            }
        }

        let combined = "\(trimmedDate) \(trimmedTime)"
        for f in dateTimeFormatters {
            if let d = f.date(from: combined) { return d }
        }
        return nil
    }

    private static func parseDate(_ str: String) -> Date? {
        for f in dateOnlyFormatters {
            if let d = f.date(from: str) { return d }
        }
        return nil
    }

    // MARK: - Cabin class mapping

    private static func parseCabinClass(_ raw: String) -> CabinClass {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case let s where s.contains("first"):            return .first
        case let s where s.contains("business"):         return .business
        case let s where s.contains("premium"):          return .premiumEconomy
        default:                                          return .economy
        }
    }

    // MARK: - Helpers

    private static func nilIfEmpty(_ s: String) -> String? {
        s.isEmpty ? nil : s
    }

    private static func preferredField(_ values: String...) -> String {
        values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
    }

    private static func normalizedAirportCode(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return "" }

        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if letters.count >= 3 {
            return String(String.UnicodeScalarView(letters.prefix(3)))
        }
        return trimmed
    }

    private static func resolvedArrivalDate(
        departureDate: Date,
        parsedArrivalDate: Date?,
        departureAirport: Airport,
        arrivalAirport: Airport,
        distanceMiles: Double
    ) -> Date {
        guard let parsedArrivalDate else {
            return departureDate.addingTimeInterval(fallbackDuration(for: distanceMiles))
        }

        let timezoneDeltaHours = approximateTimeZoneOffsetHours(for: arrivalAirport.longitude)
            - approximateTimeZoneOffsetHours(for: departureAirport.longitude)

        var duration = parsedArrivalDate.timeIntervalSince(departureDate) - (Double(timezoneDeltaHours) * 3600)

        while duration <= 0 {
            duration += 24 * 3600
        }

        let fallbackDuration = fallbackDuration(for: distanceMiles)
        if duration < 20 * 60 || duration > 22 * 3600 {
            duration = fallbackDuration
        }

        return departureDate.addingTimeInterval(duration)
    }

    private static func approximateTimeZoneOffsetHours(for longitude: Double) -> Int {
        Int((longitude / 15).rounded())
    }

    private static func fallbackDuration(for distanceMiles: Double) -> TimeInterval {
        guard distanceMiles > 0 else { return 2 * 3600 }

        let averageCruiseSpeedMph = 540.0
        let blockTimeBufferSeconds: TimeInterval = 45 * 60
        let cruiseSeconds = (distanceMiles / averageCruiseSpeedMph) * 3600
        return max(45 * 60, cruiseSeconds + blockTimeBufferSeconds)
    }
}
