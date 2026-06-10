import SwiftUI

struct FlightRowView: View {
    let flight: Flight

    private var carrierCode: String {
        AirlineIdentity.carrierCode(for: flight)
    }

    private var displayFlightCode: String {
        AirlineIdentity.displayFlightCode(for: flight)
    }

    private var displayAirlineName: String? {
        AirlineIdentity.displayAirlineName(for: flight)
    }

    private var formattedDate: String {
        DateFormatters.logbookDate.string(from: flight.departureDate)
    }

    private var metaLabel: String {
        if flight.isUpcoming {
            return "Departs in \(FlightTimeFormatting.countdownString(until: flight.departureDate))"
        }
        return flight.durationFormatted
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AirlineBadge(code: carrierCode, isUpcoming: flight.isUpcoming)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(displayFlightCode)
                            .font(.flightCode(15, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(flight.routeString)
                            .font(.flightCode(14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    Text(formattedDate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(flight.isUpcoming ? .soraAmber : .secondary)
                        .lineLimit(1)
                }

                Text("\(flight.departureAirport.city) to \(flight.arrivalAirport.city)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.92)
                    .layoutPriority(1)

                HStack(spacing: 8) {
                    if let displayAirlineName {
                        Text(displayAirlineName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("•")
                            .foregroundStyle(.tertiary)
                    }

                    if flight.isUpcoming {
                        Text("Planned")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.soraAmber.opacity(0.18))
                            .foregroundStyle(.soraAmber)
                            .clipShape(Capsule())
                    }

                    Text(metaLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(flight.isUpcoming ? .soraAmber : .secondary)

                    CabinBadge(cabin: flight.cabinClass)
                }
            }
        }
        .padding(.vertical, 10)
        .foregroundStyle(.primary)
    }
}

private struct AirlineBadge: View {
    let code: String
    let isUpcoming: Bool

    private var style: AirlineBadgeStyle {
        AirlineBadgeStyle.style(for: code)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            style.base.opacity(isUpcoming ? 0.36 : 0.28),
                            style.base.opacity(isUpcoming ? 0.22 : 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.base.opacity(isUpcoming ? 0.4 : 0.25), lineWidth: 1)
            Text(code)
                .font(.flightCode(13, weight: .bold))
                .foregroundStyle(style.base)
        }
        .frame(width: 46, height: 46)
    }
}

private enum DateFormatters {
    static let logbookDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

private struct AirlineBadgeStyle {
    let base: Color

    static func style(for code: String) -> AirlineBadgeStyle {
        switch code {
        case "DL": return .init(base: .red)
        case "VS": return .init(base: .pink)
        case "AS": return .init(base: .blue)
        case "CX": return .init(base: .teal)
        case "KL": return .init(base: .cyan)
        case "BA": return .init(base: .indigo)
        case "UA": return .init(base: .blue)
        case "AA": return .init(base: .gray)
        case "TG": return .init(base: .purple)
        case "QF": return .init(base: .red)
        case "SQ": return .init(base: .orange)
        case "EK": return .init(base: .red)
        case "AF": return .init(base: .indigo)
        case "LH": return .init(base: .yellow)
        case "NH": return .init(base: .blue)
        case "JL": return .init(base: .red)
        default: return .init(base: .soraAccent)
        }
    }
}

private enum AirlineIdentity {
    static func carrierCode(for flight: Flight) -> String {
        if let prefix = letterPrefix(from: flight.flightNumber), prefix.count >= 2 {
            return normalizeCarrierCode(String(prefix.prefix(3)))
        }

        let airline = cleanedAirlineField(flight.airline)
        if airline.count == 2 || airline.count == 3 {
            return normalizeCarrierCode(airline)
        }

        if let mapped = mappings[airline.lowercased()] {
            return mapped
        }

        let initials = flight.airline
            .split(separator: " ")
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()

        if initials.count >= 2 {
            return normalizeCarrierCode(String(initials.prefix(3)))
        }

        return "FL"
    }

    static func displayFlightCode(for flight: Flight) -> String {
        let carrier = carrierCode(for: flight)
        let digits = numericPart(from: flight.flightNumber)
        let letters = letterPrefix(from: flight.flightNumber)

        if let letters, !letters.isEmpty, flight.flightNumber.uppercased().filter({ !$0.isWhitespace }).hasPrefix(letters) {
            return flight.formattedFlightNumber
        }

        if let digits, !digits.isEmpty {
            return "\(carrier)\(digits)"
        }

        return carrier
    }

    static func displayAirlineName(for flight: Flight) -> String? {
        let airline = flight.airline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !airline.isEmpty else { return nil }

        let uppercased = airline.uppercased()
        if uppercased.count == 2 || uppercased.count == 3 {
            return airlineNamesByCode[normalizeCarrierCode(uppercased)] ?? normalizeCarrierCode(uppercased)
        }

        if let mapped = airlineNamesByName[airline.lowercased()] {
            return mapped
        }

        return airline
    }

    private static func normalizeCarrierCode(_ code: String) -> String {
        operatorToMarketingCode[code.uppercased()] ?? code.uppercased()
    }

    private static func cleanedAirlineField(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func letterPrefix(from value: String) -> String? {
        let prefix = String(value.uppercased().prefix { $0.isLetter })
        return prefix.isEmpty ? nil : prefix
    }

    private static func numericPart(from value: String) -> String? {
        let digits = value.filter { $0.isNumber }
        return digits.isEmpty ? nil : digits
    }

    private static let mappings: [String: String] = [
        "delta": "DL",
        "delta air lines": "DL",
        "virgin atlantic": "VS",
        "virgin atlantic airways": "VS",
        "united": "UA",
        "united airlines": "UA",
        "american airlines": "AA",
        "southwest": "WN",
        "southwest airlines": "WN",
        "alaska airlines": "AS",
        "jetblue": "B6",
        "british airways": "BA",
        "virgin australia": "VA",
        "lufthansa": "LH",
        "air france": "AF",
        "klm": "KL",
        "thai": "TG",
        "thai airways": "TG",
        "qantas": "QF",
        "singapore airlines": "SQ",
        "emirates": "EK",
        "cathay pacific": "CX",
        "ana": "NH",
        "all nippon airways": "NH",
        "japan airlines": "JL"
    ]

    private static let operatorToMarketingCode: [String: String] = [
        "DAL": "DL",
        "VIR": "VS",
        "ASA": "AS",
        "CPA": "CX",
        "THA": "TG",
        "BAW": "BA",
        "UAL": "UA",
        "AAL": "AA",
        "JBU": "B6",
        "QFA": "QF",
        "KLM": "KL",
        "AFR": "AF",
        "DLH": "LH",
        "SIA": "SQ",
        "UAE": "EK",
        "ANA": "NH",
        "JAL": "JL"
    ]

    private static let airlineNamesByCode: [String: String] = [
        "DL": "Delta Air Lines",
        "VS": "Virgin Atlantic",
        "AS": "Alaska Airlines",
        "CX": "Cathay Pacific",
        "TG": "Thai Airways",
        "BA": "British Airways",
        "UA": "United Airlines",
        "AA": "American Airlines",
        "B6": "JetBlue",
        "QF": "Qantas",
        "KL": "KLM",
        "AF": "Air France",
        "LH": "Lufthansa",
        "SQ": "Singapore Airlines",
        "EK": "Emirates",
        "NH": "ANA",
        "JL": "Japan Airlines",
        "WN": "Southwest"
    ]

    private static let airlineNamesByName: [String: String] = [
        "delta": "Delta Air Lines",
        "delta air lines": "Delta Air Lines",
        "virgin atlantic": "Virgin Atlantic",
        "virgin atlantic airways": "Virgin Atlantic",
        "alaska airlines": "Alaska Airlines",
        "cathay pacific": "Cathay Pacific",
        "thai": "Thai Airways",
        "thai airways": "Thai Airways",
        "british airways": "British Airways",
        "united": "United Airlines",
        "united airlines": "United Airlines",
        "american airlines": "American Airlines",
        "jetblue": "JetBlue",
        "qantas": "Qantas",
        "klm": "KLM",
        "air france": "Air France",
        "lufthansa": "Lufthansa",
        "singapore airlines": "Singapore Airlines",
        "emirates": "Emirates",
        "ana": "ANA",
        "all nippon airways": "ANA",
        "japan airlines": "Japan Airlines",
        "southwest": "Southwest"
    ]
}

struct CabinBadge: View {
    let cabin: CabinClass

    var body: some View {
        Text(cabin.shortCode)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(cabin.badgeColor.opacity(0.2))
            .foregroundStyle(cabin.badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
