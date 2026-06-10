import Testing
import SwiftData
@testable import Sora

struct SoraTests {

    // MARK: - Haversine distance

    @Test func jfkToLhrDistanceIsReasonable() {
        // JFK to LHR is approximately 3450 miles
        let jfk = Airport(iataCode: "JFK", icaoCode: "KJFK", name: "JFK", city: "New York", country: "US", latitude: 40.6413, longitude: -73.7781)
        let lhr = Airport(iataCode: "LHR", icaoCode: "EGLL", name: "Heathrow", city: "London", country: "GB", latitude: 51.4700, longitude: -0.4543)
        let dist = haversineDistance(from: jfk.coordinate, to: lhr.coordinate)
        #expect(dist > 3400 && dist < 3550)
    }

    @Test func samePointDistanceIsZero() {
        let jfk = Airport(iataCode: "JFK", icaoCode: "KJFK", name: "JFK", city: "New York", country: "US", latitude: 40.6413, longitude: -73.7781)
        let dist = haversineDistance(from: jfk.coordinate, to: jfk.coordinate)
        #expect(dist < 0.001)
    }

    // MARK: - Great circle

    @Test func greatCircleReturnsCorrectPointCount() {
        let jfk = Airport(iataCode: "JFK", icaoCode: "KJFK", name: "JFK", city: "New York", country: "US", latitude: 40.6413, longitude: -73.7781)
        let lhr = Airport(iataCode: "LHR", icaoCode: "EGLL", name: "Heathrow", city: "London", country: "GB", latitude: 51.4700, longitude: -0.4543)
        let points = greatCirclePoints(from: jfk.coordinate, to: lhr.coordinate, steps: 50)
        #expect(points.count == 51) // steps + 1
    }

    @Test func greatCircleStartAndEndMatchInputs() {
        let jfk = Airport(iataCode: "JFK", icaoCode: "KJFK", name: "JFK", city: "New York", country: "US", latitude: 40.6413, longitude: -73.7781)
        let lhr = Airport(iataCode: "LHR", icaoCode: "EGLL", name: "Heathrow", city: "London", country: "GB", latitude: 51.4700, longitude: -0.4543)
        let points = greatCirclePoints(from: jfk.coordinate, to: lhr.coordinate, steps: 100)
        #expect(abs(points.first!.latitude - jfk.latitude) < 0.001)
        #expect(abs(points.last!.latitude - lhr.latitude) < 0.001)
    }

    // MARK: - CabinClass

    @Test func cabinClassRawValueRoundtrip() {
        for cabin in CabinClass.allCases {
            let restored = CabinClass(rawValue: cabin.rawValue)
            #expect(restored == cabin)
        }
    }

    // MARK: - FlightStats

    @Test func flightStatsEmptyFlights() {
        let stats = FlightStats(flights: [])
        #expect(stats.totalFlights == 0)
        #expect(stats.totalMiles == 0)
        #expect(stats.totalHours == 0)
        #expect(stats.countriesVisited.isEmpty)
    }

    @Test func flightStatsIgnoreBlankCountries() {
        let dep = Airport.placeholder(iata: "AAA")
        let arr = Airport(iataCode: "JFK", icaoCode: "KJFK", name: "JFK", city: "New York", country: "US", latitude: 40.6413, longitude: -73.7781)
        let flight = Flight(
            flightNumber: "AA100",
            airline: "Test Air",
            aircraftType: "A320",
            departureAirport: dep,
            arrivalAirport: arr,
            departureDate: .now,
            arrivalDate: .now.addingTimeInterval(3600),
            distanceMiles: 500
        )

        let stats = FlightStats(flights: [flight])
        #expect(stats.countriesVisited == ["US"])
    }

    @Test func distanceUnitKilometersFormattingUsesConvertedValue() {
        let formatted = DistanceUnit.kilometers.format(fromMiles: 100)
        #expect(formatted == "161 km")
    }

    @Test func flightyImportParsesTimeOnlyFieldsWithoutDefaultingToTwoHours() throws {
        let csv = """
        Date,Airline,Flight,From,To,Dep Terminal,Dep Gate,Arr Terminal,Arr Gate,Canceled,Diverted To,Gate Departure (Scheduled),Gate Departure (Actual),Take off (Scheduled),Take off (Actual),Landing (Scheduled),Landing (Actual),Gate Arrival (Scheduled),Gate Arrival (Actual),Aircraft Type Name,Tail Number,PNR,Seat,Seat Type,Cabin Class,Flight Reason,Notes,Flight Flighty ID,Airline Flighty ID,Departure Airport Flighty ID,Arrival Airport Flighty ID,Diverted To Airport Flighty ID,Aircraft Type Flighty ID
        2024-01-15,Delta,DL1,JFK,LAX,,,,,false,,08:00,08:15,08:20,08:23,11:05,11:02,11:15,11:12,Airbus A321,N123DL,,14A,,Economy,,Test notes,,,,,,
        """

        let container = try ModelContainer(
            for: Schema([Flight.self, AircraftType.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let result = try FlightyImportService.importCSV(contents: csv, into: context)
        let descriptor = FetchDescriptor<Flight>()
        let flights = try context.fetch(descriptor)

        #expect(result.imported == 1)
        #expect(flights.count == 1)
        #expect(flights[0].durationFormatted == "2h 39m")
        #expect(Calendar(identifier: .gregorian).component(.year, from: flights[0].departureDate) == 2024)
    }

    @Test func flightyImportSkipsDivertedFlights() throws {
        let csv = """
        Date,Airline,Flight,From,To,Dep Terminal,Dep Gate,Arr Terminal,Arr Gate,Canceled,Diverted To,Gate Departure (Scheduled),Gate Departure (Actual),Take off (Scheduled),Take off (Actual),Landing (Scheduled),Landing (Actual),Gate Arrival (Scheduled),Gate Arrival (Actual),Aircraft Type Name,Tail Number,PNR,Seat,Seat Type,Cabin Class,Flight Reason,Notes,Flight Flighty ID,Airline Flighty ID,Departure Airport Flighty ID,Arrival Airport Flighty ID,Diverted To Airport Flighty ID,Aircraft Type Flighty ID
        2024-01-15,Delta,DL1,JFK,LAX,,,,,false,SLC,08:00,08:15,08:20,08:23,11:05,11:02,11:15,11:12,Airbus A321,N123DL,,14A,,Economy,,Test notes,,,,,,
        """

        let container = try ModelContainer(
            for: Schema([Flight.self, AircraftType.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let result = try FlightyImportService.importCSV(contents: csv, into: context)
        let flights = try context.fetch(FetchDescriptor<Flight>())

        #expect(result.imported == 0)
        #expect(result.skipped == 1)
        #expect(flights.isEmpty)
    }

    @Test func flightStatsGroupsYearsCorrectly() {
        let jfk = Airport(iataCode: "JFK", icaoCode: "KJFK", name: "JFK", city: "New York", country: "US", latitude: 40.6413, longitude: -73.7781)
        let lhr = Airport(iataCode: "LHR", icaoCode: "EGLL", name: "Heathrow", city: "London", country: "GB", latitude: 51.4700, longitude: -0.4543)

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2023
        components.month = 6
        components.day = 1
        components.hour = 12
        let firstDate = components.date!

        components.year = 2024
        let secondDate = components.date!

        let flights = [
            Flight(flightNumber: "AA1", airline: "A", aircraftType: "A320", departureAirport: jfk, arrivalAirport: lhr, departureDate: firstDate, arrivalDate: firstDate.addingTimeInterval(3600), distanceMiles: 100),
            Flight(flightNumber: "AA2", airline: "A", aircraftType: "A320", departureAirport: jfk, arrivalAirport: lhr, departureDate: secondDate, arrivalDate: secondDate.addingTimeInterval(7200), distanceMiles: 200)
        ]

        let stats = FlightStats(flights: flights)
        #expect(stats.flightsByYear.map { $0.year } == [2023, 2024])
        #expect(stats.milesByYear.map { $0.miles } == [100, 200])
    }

    @Test func flightyImportParsesFlightyIsoDatetimeWithoutTimezone() throws {
        let csv = """
        Date,Airline,Flight,From,To,Dep Terminal,Dep Gate,Arr Terminal,Arr Gate,Canceled,Diverted To,Gate Departure (Scheduled),Gate Departure (Actual),Take off (Scheduled),Take off (Actual),Landing (Scheduled),Landing (Actual),Gate Arrival (Scheduled),Gate Arrival (Actual),Aircraft Type Name,Tail Number,PNR,Seat,Seat Type,Cabin Class,Flight Reason,Notes,Flight Flighty ID,Airline Flighty ID,Departure Airport Flighty ID,Arrival Airport Flighty ID,Diverted To Airport Flighty ID,Aircraft Type Flighty ID
        2008-04-18,THA,320,KTM,BKK,I,,,,false,,2008-04-18T13:50,2008-04-18T13:53,,,,,2008-04-18T18:20,2008-04-18T18:25,Boeing 777-200 ER,,,,,,,,afbf8721-724b-4faf-b926-6d63594d9a22,a0b83fd3-dea9-4db2-a20a-cf6b63e1b6af,b226a31b-a92c-4eff-81f6-adfc718270bd,548d409f-68f7-4450-aaaf-87133919af6d,,a0f171e1-86df-426a-8922-e460c0660ae6
        """

        let container = try ModelContainer(
            for: Schema([Flight.self, AircraftType.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        _ = try FlightyImportService.importCSV(contents: csv, into: context)
        let flights = try context.fetch(FetchDescriptor<Flight>())

        #expect(flights.count == 1)
        #expect(flights[0].flightNumber == "320")
        #expect(flights[0].durationFormatted == "4h 32m")
        #expect(Calendar(identifier: .gregorian).component(.year, from: flights[0].departureDate) == 2008)
    }

    @Test func flightyImportAdjustsForTimezoneLikeSfoToSyd() throws {
        let csv = """
        Date,Airline,Flight,From,To,Dep Terminal,Dep Gate,Arr Terminal,Arr Gate,Canceled,Diverted To,Gate Departure (Scheduled),Gate Departure (Actual),Take off (Scheduled),Take off (Actual),Landing (Scheduled),Landing (Actual),Gate Arrival (Scheduled),Gate Arrival (Actual),Aircraft Type Name,Tail Number,PNR,Seat,Seat Type,Cabin Class,Flight Reason,Notes,Flight Flighty ID,Airline Flighty ID,Departure Airport Flighty ID,Arrival Airport Flighty ID,Diverted To Airport Flighty ID,Aircraft Type Flighty ID
        2024-02-10,QF,74,SFO,SYD,,,,,false,,2024-02-10T22:30,2024-02-10T22:45,,,,,2024-02-12T08:10,2024-02-12T08:25,Boeing 787-9,,,,,,,,,,,,,
        """

        let container = try ModelContainer(
            for: Schema([Flight.self, AircraftType.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        _ = try FlightyImportService.importCSV(contents: csv, into: context)
        let flights = try context.fetch(FetchDescriptor<Flight>())

        #expect(flights.count == 1)
        #expect(flights[0].durationFormatted == "15h 40m")
    }
}
