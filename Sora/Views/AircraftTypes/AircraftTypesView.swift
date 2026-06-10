import SwiftUI
import SwiftData

struct AircraftTypesView: View {
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    private var aircraftStats: [(type: String, count: Int, firstFlown: Date?)] {
        let groups = Dictionary(grouping: flights) { $0.aircraftType }
        return groups.map { type, flights in
            let firstFlown = flights.map { $0.departureDate }.min()
            return (type, flights.count, firstFlown)
        }
        .filter { !$0.type.isEmpty }
        .sorted { $0.count > $1.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if aircraftStats.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "paperplane.circle")
                            .font(.system(size: 64))
                            .foregroundStyle(.soraAccent.opacity(0.5))
                        Text("No Aircraft Yet")
                            .font(.title3.bold())
                        Text("Log flights to see your aircraft types here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(aircraftStats, id: \.type) { item in
                                NavigationLink(
                                    destination: AircraftFlightsView(
                                        aircraftType: item.type,
                                        flights: flights.filter { $0.aircraftType == item.type }
                                    )
                                ) {
                                    AircraftTypeCard(
                                        type: item.type,
                                        count: item.count,
                                        firstFlown: item.firstFlown
                                    )
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.soraNavy.ignoresSafeArea())
            .navigationTitle("Aircraft")
        }
    }
}

// MARK: - Card

private struct AircraftTypeCard: View {
    let type: String
    let count: Int
    let firstFlown: Date?

    // Split "Boeing 737-800" → manufacturer + model
    private var manufacturer: String {
        let parts = type.components(separatedBy: " ")
        return parts.first ?? type
    }
    private var model: String {
        let parts = type.components(separatedBy: " ")
        return parts.dropFirst().joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Manufacturer
            Text(manufacturer)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Model — large
            Text(model.isEmpty ? type : model)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            HStack {
                // Flight count
                Label("\(count)", systemImage: "airplane")
                    .font(.caption.bold())
                    .foregroundStyle(.soraAccent)

                Spacer()

                // First flown
                if let date = firstFlown {
                    Text(date.formatted(.dateTime.year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(Color.soraCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.soraAccent.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Aircraft flights list

private struct AircraftFlightsView: View {
    let aircraftType: String
    let flights: [Flight]

    var body: some View {
        List(flights) { flight in
            NavigationLink(destination: FlightDetailView(flight: flight)) {
                FlightRowView(flight: flight)
            }
            .listRowBackground(Color.soraCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.soraNavy.ignoresSafeArea())
        .navigationTitle(aircraftType)
        .navigationBarTitleDisplayMode(.inline)
    }
}
