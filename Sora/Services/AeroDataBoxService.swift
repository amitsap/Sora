import Foundation
import Observation

// MARK: - Result types

struct FlightLookupResult {
    var flightNumber: String
    var airline: String
    var departureAirport: Airport
    var arrivalAirport: Airport
    var departureDate: Date
    var arrivalDate: Date
    var aircraftType: String
    var aircraftRegistration: String?
    var distanceMiles: Double
}

struct UpcomingFlightStatus {
    var statusText: String
    var departureScheduled: Date?
    var departureUpdated: Date?
    var arrivalScheduled: Date?
    var arrivalUpdated: Date?
    var departureTerminal: String?
    var departureGate: String?
    var arrivalTerminal: String?
    var arrivalGate: String?
    var aircraftType: String?
    var aircraftRegistration: String?
    var airline: String?

    var effectiveDeparture: Date? { departureUpdated ?? departureScheduled }
    var effectiveArrival: Date? { arrivalUpdated ?? arrivalScheduled }
}

enum AeroDataBoxError: LocalizedError {
    case noAPIKey
    case flightNotFound
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No AeroDataBox API key set. Add your key in Settings."
        case .flightNotFound:
            return "Flight not found. Check the flight number and date."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Could not parse flight data."
        }
    }
}

// MARK: - Raw API decodables

private struct ADBFlightResponse: Decodable {
    let status: String?
    let departure: ADBEndpoint?
    let arrival: ADBEndpoint?
    let airline: ADBItemName?
    let aircraft: ADBAircraft?

    struct ADBEndpoint: Decodable {
        let airport: ADBAirport?
        let terminal: String?
        let gate: String?
        let scheduledTime: ADBTime?
        let revisedTime: ADBTime?
        let actualTime: ADBTime?
    }

    struct ADBAirport: Decodable {
        let iata: String?
        let icao: String?
        let name: String?
        let municipalityName: String?
        let countryCode: String?
        let location: ADBLocation?
    }

    struct ADBLocation: Decodable {
        let lat: Double?
        let lon: Double?
    }

    struct ADBTime: Decodable {
        let utc: String?
        let local: String?
    }

    struct ADBItemName: Decodable {
        let name: String?
        let iata: String?
    }

    struct ADBAircraft: Decodable {
        let model: String?
        let reg: String?
    }
}

private struct ADBAirportResponse: Decodable {
    let iata: String?
    let icao: String?
    let fullName: String?
    let municipalityName: String?
    let countryCode: String?
    let location: ADBFlightResponse.ADBLocation?
}

// MARK: - Service

@Observable
final class AeroDataBoxService {
    private let baseURL = "https://aerodatabox.p.rapidapi.com"
    private let host = "aerodatabox.p.rapidapi.com"

    // AeroDataBox returns UTC times in format "2024-01-15 13:00Z"
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mmz"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(abbreviation: "UTC")
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var apiKey: String {
        get { KeychainService.load(key: KeychainService.aeroDataBoxKey) ?? "" }
        set { KeychainService.save(key: KeychainService.aeroDataBoxKey, value: newValue) }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    // MARK: Flight lookup

    func lookupFlight(flightNumber: String, date: Date) async throws -> FlightLookupResult {
        let flight = try await fetchFlight(flightNumber: flightNumber, date: date)
        let cleaned = flightNumber.uppercased().replacingOccurrences(of: " ", with: "")
        return try buildResult(from: flight, flightNumber: cleaned, date: date)
    }

    func lookupUpcomingStatus(flightNumber: String, date: Date) async throws -> UpcomingFlightStatus {
        let flight = try await fetchFlight(flightNumber: flightNumber, date: date)
        return buildUpcomingStatus(from: flight)
    }

    private func fetchFlight(flightNumber: String, date: Date) async throws -> ADBFlightResponse {
        guard hasAPIKey else { throw AeroDataBoxError.noAPIKey }

        let dateString = dateFormatter.string(from: date)
        let cleaned = flightNumber.uppercased().replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: "\(baseURL)/flights/number/\(cleaned)/\(dateString)") else {
            throw AeroDataBoxError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue(host, forHTTPHeaderField: "X-RapidAPI-Host")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AeroDataBoxError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 404: throw AeroDataBoxError.flightNotFound
            case 401, 403: throw AeroDataBoxError.noAPIKey
            default: throw AeroDataBoxError.networkError(URLError(.badServerResponse))
            }
        }

        guard let flights = try? JSONDecoder().decode([ADBFlightResponse].self, from: data),
              let flight = flights.first else {
            throw AeroDataBoxError.decodingError
        }
        return flight
    }

    // MARK: Airport lookup

    func lookupAirport(iata: String) async throws -> Airport {
        guard hasAPIKey else { throw AeroDataBoxError.noAPIKey }

        guard let url = URL(string: "\(baseURL)/airports/iata/\(iata.uppercased())") else {
            throw AeroDataBoxError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue(host, forHTTPHeaderField: "X-RapidAPI-Host")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AeroDataBoxError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw AeroDataBoxError.flightNotFound
        }

        guard let raw = try? JSONDecoder().decode(ADBAirportResponse.self, from: data),
              let iataCode = raw.iata else {
            throw AeroDataBoxError.decodingError
        }

        return Airport(
            iataCode: iataCode,
            icaoCode: raw.icao ?? "",
            name: raw.fullName ?? iataCode,
            city: raw.municipalityName ?? iataCode,
            country: raw.countryCode ?? "",
            latitude: raw.location?.lat ?? 0,
            longitude: raw.location?.lon ?? 0
        )
    }

    // MARK: Private helpers

    private func buildResult(
        from flight: ADBFlightResponse,
        flightNumber: String,
        date: Date
    ) throws -> FlightLookupResult {
        guard
            let depRaw = flight.departure?.airport,
            let arrRaw = flight.arrival?.airport,
            let depIATA = depRaw.iata,
            let arrIATA = arrRaw.iata
        else { throw AeroDataBoxError.decodingError }

        let dep = Airport(
            iataCode: depIATA,
            icaoCode: depRaw.icao ?? "",
            name: depRaw.name ?? depIATA,
            city: depRaw.municipalityName ?? depIATA,
            country: depRaw.countryCode ?? "",
            latitude: depRaw.location?.lat ?? 0,
            longitude: depRaw.location?.lon ?? 0
        )

        let arr = Airport(
            iataCode: arrIATA,
            icaoCode: arrRaw.icao ?? "",
            name: arrRaw.name ?? arrIATA,
            city: arrRaw.municipalityName ?? arrIATA,
            country: arrRaw.countryCode ?? "",
            latitude: arrRaw.location?.lat ?? 0,
            longitude: arrRaw.location?.lon ?? 0
        )

        // Prefer actual > revised > scheduled time
        let depTimeStr = flight.departure?.actualTime?.utc
            ?? flight.departure?.revisedTime?.utc
            ?? flight.departure?.scheduledTime?.utc
        let arrTimeStr = flight.arrival?.actualTime?.utc
            ?? flight.arrival?.revisedTime?.utc
            ?? flight.arrival?.scheduledTime?.utc

        let depDate = depTimeStr.flatMap { timeFormatter.date(from: $0) } ?? date
        let arrDate = arrTimeStr.flatMap { timeFormatter.date(from: $0) } ?? date.addingTimeInterval(7200)
        let distance = haversineDistance(from: dep.coordinate, to: arr.coordinate)

        return FlightLookupResult(
            flightNumber: flightNumber,
            airline: flight.airline?.name ?? "",
            departureAirport: dep,
            arrivalAirport: arr,
            departureDate: depDate,
            arrivalDate: arrDate,
            aircraftType: flight.aircraft?.model ?? "",
            aircraftRegistration: flight.aircraft?.reg,
            distanceMiles: distance
        )
    }

    private func buildUpcomingStatus(from flight: ADBFlightResponse) -> UpcomingFlightStatus {
        UpcomingFlightStatus(
            statusText: normalizedStatusText(flight.status),
            departureScheduled: parseADBTime(flight.departure?.scheduledTime),
            departureUpdated: parseADBTime(flight.departure?.actualTime) ?? parseADBTime(flight.departure?.revisedTime),
            arrivalScheduled: parseADBTime(flight.arrival?.scheduledTime),
            arrivalUpdated: parseADBTime(flight.arrival?.actualTime) ?? parseADBTime(flight.arrival?.revisedTime),
            departureTerminal: nonEmpty(flight.departure?.terminal),
            departureGate: nonEmpty(flight.departure?.gate),
            arrivalTerminal: nonEmpty(flight.arrival?.terminal),
            arrivalGate: nonEmpty(flight.arrival?.gate),
            aircraftType: nonEmpty(flight.aircraft?.model),
            aircraftRegistration: nonEmpty(flight.aircraft?.reg),
            airline: nonEmpty(flight.airline?.name)
        )
    }

    private func parseADBTime(_ time: ADBFlightResponse.ADBTime?) -> Date? {
        guard let raw = time?.utc ?? time?.local else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }

        let fallbackISO = ISO8601DateFormatter()
        fallbackISO.formatOptions = [.withInternetDateTime]
        if let date = fallbackISO.date(from: raw) { return date }

        return timeFormatter.date(from: raw)
    }

    private func normalizedStatusText(_ raw: String?) -> String {
        guard let raw = nonEmpty(raw) else { return "Scheduled" }
        return raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
