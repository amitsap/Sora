import SwiftUI
import SwiftData

struct HomeView: View {
    let onAddFlight: (FlightDraft) -> Void

    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    private var stats: FlightStats { FlightStats(flights: flights) }

    private var upcomingFlights: [Flight] {
        flights
            .filter { $0.isUpcoming }
            .sorted { $0.departureDate < $1.departureDate }
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit.current
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    FullMapView()
                        .frame(height: 420)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    VStack(spacing: 20) {
                        statsStrip

                        if !upcomingFlights.isEmpty {
                            upcomingFlightsSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 96)
                }
                .background(Color.soraNavy.ignoresSafeArea())

                if flights.isEmpty {
                    VStack {
                        Spacer()
                        emptyState
                            .padding(.horizontal, 16)
                            .padding(.bottom, 96)
                    }
                }

                Button(action: { onAddFlight(.empty) }) {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.soraAccent)
                        .clipShape(Circle())
                        .shadow(color: .soraAccent.opacity(0.45), radius: 14, y: 5)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 18)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 12) {
            CompactStatCard(value: "\(stats.totalFlights)", label: "Flights", icon: "airplane")
            CompactStatCard(value: stats.totalMilesFormatted, label: distanceUnit.displayName, icon: "map")
            CompactStatCard(value: stats.totalDaysFormatted, label: "Days", icon: "clock")
            CompactStatCard(value: "\(stats.countriesVisited.count)", label: "Countries", icon: "globe")
        }
    }

    private var upcomingFlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Flights")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 1) {
                ForEach(upcomingFlights.prefix(3)) { flight in
                    NavigationLink(destination: FlightDetailView(flight: flight)) {
                        UpcomingFlightCard(flight: flight)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.soraCard)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 60))
                .foregroundStyle(.soraAccent.opacity(0.8))

            VStack(spacing: 6) {
                Text("Your logbook is empty")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Tap + to add your first flight and start building your map.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(Color.soraCard.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct CompactStatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.soraAccent)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.soraCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct UpcomingFlightCard: View {
    let flight: Flight

    private var departureDateText: String {
        flight.departureDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var departureTimeText: String {
        flight.departureDate.formatted(date: .omitted, time: .shortened)
    }

    private var countdownText: String {
        FlightTimeFormatting.countdownString(until: flight.departureDate)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(flight.formattedFlightNumber)
                        .font(.flightCode(15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(flight.routeString)
                        .font(.flightCode(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("\(flight.departureAirport.city) to \(flight.arrivalAirport.city)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(flight.airline.isEmpty ? "Upcoming flight" : flight.airline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("In \(countdownText)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.soraAmber)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(departureDateText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(departureTimeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
