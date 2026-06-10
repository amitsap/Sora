import SwiftUI

struct AirportSearchView: View {
    @Environment(AeroDataBoxService.self) private var aeroDataBox
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSelect: (Airport) -> Void

    @State private var query = ""
    @State private var result: Airport?
    @State private var isLooking = false
    @State private var errorMessage: String?

    // Common airports for quick selection when no API key
    private let commonAirports: [Airport] = [
        Airport(iataCode: "JFK", icaoCode: "KJFK", name: "John F. Kennedy International", city: "New York", country: "US", latitude: 40.6413, longitude: -73.7781),
        Airport(iataCode: "LAX", icaoCode: "KLAX", name: "Los Angeles International", city: "Los Angeles", country: "US", latitude: 33.9416, longitude: -118.4085),
        Airport(iataCode: "LHR", icaoCode: "EGLL", name: "Heathrow Airport", city: "London", country: "GB", latitude: 51.4700, longitude: -0.4543),
        Airport(iataCode: "CDG", icaoCode: "LFPG", name: "Charles de Gaulle Airport", city: "Paris", country: "FR", latitude: 49.0097, longitude: 2.5479),
        Airport(iataCode: "NRT", icaoCode: "RJAA", name: "Narita International Airport", city: "Tokyo", country: "JP", latitude: 35.7720, longitude: 140.3929),
        Airport(iataCode: "DXB", icaoCode: "OMDB", name: "Dubai International Airport", city: "Dubai", country: "AE", latitude: 25.2532, longitude: 55.3657),
        Airport(iataCode: "SYD", icaoCode: "YSSY", name: "Kingsford Smith Airport", city: "Sydney", country: "AU", latitude: -33.9399, longitude: 151.1753),
        Airport(iataCode: "SFO", icaoCode: "KSFO", name: "San Francisco International", city: "San Francisco", country: "US", latitude: 37.6213, longitude: -122.3790),
        Airport(iataCode: "ORD", icaoCode: "KORD", name: "O'Hare International Airport", city: "Chicago", country: "US", latitude: 41.9742, longitude: -87.9073),
        Airport(iataCode: "SIN", icaoCode: "WSSS", name: "Singapore Changi Airport", city: "Singapore", country: "SG", latitude: 1.3644, longitude: 103.9915),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("IATA code (e.g. JFK)", text: $query)
                        .font(.flightCode(17))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { lookupAirport() }
                    if isLooking {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !query.isEmpty {
                        Button(action: lookupAirport) {
                            Text("Look Up")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.soraAccent)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(14)
                .background(Color.soraCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top)

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Result
                if let result {
                    Button(action: { onSelect(result); dismiss() }) {
                        AirportRow(airport: result, highlight: true)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }

                // Quick picks
                if result == nil {
                    List {
                        Section {
                            Text(!aeroDataBox.hasAPIKey
                                 ? "Add your AeroDataBox API key in Settings to search any airport by IATA code. Common airports shown below."
                                 : "Type an IATA code above to search, or pick a common airport.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.soraCard)
                        }

                        Section("Common Airports") {
                            ForEach(commonAirports) { airport in
                                Button(action: { onSelect(airport); dismiss() }) {
                                    AirportRow(airport: airport, highlight: false)
                                }
                                .listRowBackground(Color.soraCard)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }

                Spacer()

                // Manual entry fallback
                if !query.isEmpty && result == nil && !isLooking {
                    Button(action: {
                        onSelect(Airport.placeholder(iata: query))
                        dismiss()
                    }) {
                        Label("Use \"\(query.uppercased())\" as IATA code", systemImage: "pencil")
                            .font(.subheadline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.soraCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                    }
                    .padding(.bottom)
                }
            }
            .background(Color.soraNavy.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func lookupAirport() {
        guard !query.isEmpty else { return }
        guard aeroDataBox.hasAPIKey else {
            errorMessage = "No API key — using IATA code directly."
            result = Airport.placeholder(iata: query)
            return
        }
        isLooking = true
        errorMessage = nil
        let iata = query.uppercased()
        Task {
            do {
                result = try await aeroDataBox.lookupAirport(iata: iata)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLooking = false
        }
    }
}

struct AirportRow: View {
    let airport: Airport
    let highlight: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(airport.iataCode)
                .font(.flightCode(18, weight: .bold))
                .foregroundStyle(highlight ? .soraAccent : .primary)
                .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(airport.name.isEmpty ? airport.iataCode : airport.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(airport.city), \(airport.country)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, highlight ? 14 : 0)
        .background(highlight ? Color.soraCard : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
