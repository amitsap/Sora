import Foundation
import Observation
import CoreLocation

struct OpenSkyAircraft: Identifiable, Sendable {
    let id: String
    let callsign: String
    let coordinate: CLLocationCoordinate2D
    let trueTrack: Double?
    let velocityMetersPerSecond: Double?
    let barometricAltitudeMeters: Double?
    let lastContact: Date

    var speedKnots: Double? {
        velocityMetersPerSecond.map { $0 * 1.94384 }
    }
}

struct GeoBounds: Sendable, Equatable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    var isZoomedForLiveTraffic: Bool {
        (maxLatitude - minLatitude) <= 45 && (maxLongitude - minLongitude) <= 90
    }
}

enum OpenSkyError: LocalizedError {
    case missingCredentials
    case authenticationFailed
    case badServerResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Add your OpenSky client ID and secret in Settings."
        case .authenticationFailed:
            return "OpenSky authentication failed. Check your client ID and secret."
        case .badServerResponse:
            return "OpenSky returned an unexpected response."
        }
    }
}

private struct OpenSkyTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private struct OpenSkyStatesResponse: Decodable {
    let time: Int?
    let states: [[OpenSkyStateValue]?]?
}

private enum OpenSkyStateValue: Decodable {
    case string(String)
    case double(Double)
    case int(Int)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        case .string(let value): return Double(value)
        case .bool, .null: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        case .bool, .null: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return Bool(value)
        case .int(let value): return value != 0
        case .double(let value): return value != 0
        case .null: return nil
        }
    }
}

@MainActor
@Observable
final class OpenSkyService {
    private let authURL = URL(string: "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token")!
    private let statesURL = URL(string: "https://opensky-network.org/api/states/all")!

    private var accessToken: String?
    private var accessTokenExpiry: Date?

    var clientID: String {
        get { KeychainService.load(key: KeychainService.openSkyClientIDKey) ?? "" }
        set { KeychainService.save(key: KeychainService.openSkyClientIDKey, value: newValue) }
    }

    var clientSecret: String {
        get { KeychainService.load(key: KeychainService.openSkyClientSecretKey) ?? "" }
        set { KeychainService.save(key: KeychainService.openSkyClientSecretKey, value: newValue) }
    }

    var hasCredentials: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    func fetchAircraft(in bounds: GeoBounds) async throws -> [OpenSkyAircraft] {
        guard hasCredentials else { throw OpenSkyError.missingCredentials }
        let token = try await validAccessToken()

        var components = URLComponents(url: statesURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lamin", value: String(bounds.minLatitude)),
            URLQueryItem(name: "lamax", value: String(bounds.maxLatitude)),
            URLQueryItem(name: "lomin", value: String(bounds.minLongitude)),
            URLQueryItem(name: "lomax", value: String(bounds.maxLongitude))
        ]

        guard let url = components?.url else {
            throw OpenSkyError.badServerResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenSkyError.badServerResponse
        }

        if http.statusCode == 401 {
            accessToken = nil
            accessTokenExpiry = nil
            throw OpenSkyError.authenticationFailed
        }

        guard http.statusCode == 200 else {
            throw OpenSkyError.badServerResponse
        }

        let payload = try JSONDecoder().decode(OpenSkyStatesResponse.self, from: data)
        let responseTime = Date(timeIntervalSince1970: TimeInterval(payload.time ?? Int(Date().timeIntervalSince1970)))

        return (payload.states ?? [])
            .compactMap { $0 }
            .compactMap { state in
                guard state.count >= 17,
                      let icao24 = state[safe: 0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let longitude = state[safe: 5]?.doubleValue,
                      let latitude = state[safe: 6]?.doubleValue,
                      let onGround = state[safe: 8]?.boolValue,
                      !onGround else {
                    return nil
                }

                let lastContactSeconds = state[safe: 4]?.intValue ?? Int(responseTime.timeIntervalSince1970)
                return OpenSkyAircraft(
                    id: icao24,
                    callsign: state[safe: 1]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    trueTrack: state[safe: 10]?.doubleValue,
                    velocityMetersPerSecond: state[safe: 9]?.doubleValue,
                    barometricAltitudeMeters: state[safe: 7]?.doubleValue,
                    lastContact: Date(timeIntervalSince1970: TimeInterval(lastContactSeconds))
                )
            }
    }

    private func validAccessToken() async throws -> String {
        if let token = accessToken,
           let expiry = accessTokenExpiry,
           expiry > Date().addingTimeInterval(60) {
            return token
        }

        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials&client_id=\(percentEncoded(clientID))&client_secret=\(percentEncoded(clientSecret))"
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenSkyError.badServerResponse
        }
        guard http.statusCode == 200 else {
            throw OpenSkyError.authenticationFailed
        }

        let payload = try JSONDecoder().decode(OpenSkyTokenResponse.self, from: data)
        accessToken = payload.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        return payload.accessToken
    }

    private func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
