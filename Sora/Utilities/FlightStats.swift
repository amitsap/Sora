import Foundation

struct FlightStats {
    let totalFlights: Int
    let totalMiles: Double
    let totalHours: Double
    let countriesVisited: [String]
    let airportsVisited: [Airport]
    let airlinesFlown: [(airline: String, count: Int)]
    let aircraftTypesFlown: [(type: String, count: Int)]
    let longestFlight: Flight?
    let shortestFlight: Flight?
    let longestByDistance: Flight?
    let mostVisitedAirport: (airport: Airport, count: Int)?
    let mostFlownRoute: (departure: Airport, arrival: Airport, count: Int)?
    let flightsByYear: [(year: Int, count: Int)]
    let milesByYear: [(year: Int, miles: Double)]
    let flightsByCabin: [(cabin: CabinClass, count: Int)]
    let flightsThisYear: Int
    let averageDistanceMiles: Double
    let averageDurationHours: Double

    init(flights: [Flight]) {
        let now = Date()
        let completed = flights.filter { $0.isCompleted && $0.departureDate <= now }

        totalFlights = completed.count
        totalMiles = completed.reduce(0) { $0 + $1.distanceMiles }
        totalHours = completed.reduce(0) { $0 + $1.duration } / 3600
        averageDistanceMiles = totalFlights == 0 ? 0 : totalMiles / Double(totalFlights)
        averageDurationHours = totalFlights == 0 ? 0 : totalHours / Double(totalFlights)

        // Countries — deduplicated, sorted
        let countries = completed.flatMap {
            [$0.departureAirport.country, $0.arrivalAirport.country]
        }
        countriesVisited = Array(Set(countries.filter { !$0.isEmpty })).sorted()

        // Airports — deduplicated by IATA
        var airportMap: [String: Airport] = [:]
        for flight in completed {
            airportMap[flight.departureAirport.iataCode] = flight.departureAirport
            airportMap[flight.arrivalAirport.iataCode] = flight.arrivalAirport
        }
        airportsVisited = Array(airportMap.values).sorted { $0.iataCode < $1.iataCode }

        // Airlines by frequency
        let airlineGroups = Dictionary(grouping: completed, by: { $0.airline })
        airlinesFlown = airlineGroups.map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count }

        // Aircraft types by frequency
        let typeGroups = Dictionary(grouping: completed, by: { $0.aircraftType })
        aircraftTypesFlown = typeGroups.map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count }

        // Longest / shortest
        longestFlight = completed.max(by: { $0.duration < $1.duration })
        shortestFlight = completed.min(by: { $0.duration < $1.duration })
        longestByDistance = completed.max(by: { $0.distanceMiles < $1.distanceMiles })

        // Most visited airport
        var visitCounts: [String: (Airport, Int)] = [:]
        for flight in completed {
            let dep = flight.departureAirport
            let arr = flight.arrivalAirport
            visitCounts[dep.iataCode] = (dep, (visitCounts[dep.iataCode]?.1 ?? 0) + 1)
            visitCounts[arr.iataCode] = (arr, (visitCounts[arr.iataCode]?.1 ?? 0) + 1)
        }
        if let top = visitCounts.values.max(by: { $0.1 < $1.1 }) {
            mostVisitedAirport = (top.0, top.1)
        } else {
            mostVisitedAirport = nil
        }

        // Most flown route
        let routeGroups = Dictionary(grouping: completed) { flight in
            "\(flight.departureAirport.iataCode)-\(flight.arrivalAirport.iataCode)"
        }
        if let topRoute = routeGroups.max(by: { $0.value.count < $1.value.count }),
           let sample = topRoute.value.first {
            mostFlownRoute = (sample.departureAirport, sample.arrivalAirport, topRoute.value.count)
        } else {
            mostFlownRoute = nil
        }

        // By year
        let calendar = Calendar.current
        let yearGroups = Dictionary(grouping: completed) {
            calendar.component(.year, from: $0.departureDate)
        }
        flightsThisYear = yearGroups[calendar.component(.year, from: Date())]?.count ?? 0
        flightsByYear = yearGroups.map { ($0.key, $0.value.count) }
            .sorted { $0.year < $1.year }
        milesByYear = yearGroups.map { ($0.key, $0.value.reduce(0) { $0 + $1.distanceMiles }) }
            .sorted { $0.year < $1.year }

        // By cabin class
        let cabinGroups = Dictionary(grouping: completed, by: { $0.cabinClass })
        flightsByCabin = CabinClass.allCases.compactMap { cabin in
            guard let count = cabinGroups[cabin]?.count, count > 0 else { return nil }
            return (cabin, count)
        }
    }

    var totalHoursFormatted: String {
        let hours = Int(totalHours)
        let minutes = Int((totalHours - Double(hours)) * 60)
        return "\(hours)h \(minutes)m"
    }

    var totalMilesFormatted: String {
        DistanceUnit.current.format(fromMiles: totalMiles, includeUnit: false)
    }

    var totalDaysFormatted: String {
        let days = totalHours / 24
        if days >= 10 {
            return String(format: "%.0f", days)
        }
        return String(format: "%.1f", days)
    }

    var averageDistanceFormatted: String {
        DistanceUnit.current.format(fromMiles: averageDistanceMiles)
    }

    var averageDurationFormatted: String {
        let totalMinutes = Int((averageDurationHours * 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }
}
