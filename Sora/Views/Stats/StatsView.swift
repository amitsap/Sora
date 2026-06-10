import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    private var stats: FlightStats { FlightStats(flights: flights) }

    var body: some View {
        NavigationStack {
            Group {
                if flights.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 64))
                            .foregroundStyle(.soraAccent.opacity(0.5))
                        Text("No stats yet")
                            .font(.title3.bold())
                        Text("Log some flights to see your statistics.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            heroNumbers
                            highlightsCard
                            flightsByYearChart
                            cabinClassChart
                            milesByYearChart
                            countriesCard
                            airlinesCard
                            aircraftCard
                            recordsCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .background(Color.soraNavy.ignoresSafeArea())
            .navigationTitle("Statistics")
        }
    }

    // MARK: Hero numbers

    private var heroNumbers: some View {
        let distanceUnit = DistanceUnit.current
        return HStack(spacing: 12) {
            BigStatCard(
                value: "\(stats.totalFlights)",
                label: "Total Flights",
                icon: "airplane",
                color: .soraAccent
            )
            BigStatCard(
                value: stats.totalMilesFormatted,
                label: "Total \(distanceUnit.displayName)",
                icon: "map",
                color: .soraAmber
            )
            BigStatCard(
                value: stats.totalDaysFormatted,
                label: "Days Airborne",
                icon: "clock",
                color: Color(red: 0.4, green: 0.85, blue: 0.55)
            )
        }
    }

    // MARK: Charts

    private var highlightsCard: some View {
        StatsCard(title: "Highlights", icon: "sparkles") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MiniMetricCard(
                    title: "Airports",
                    value: "\(stats.airportsVisited.count)",
                    subtitle: "visited",
                    color: .soraAccent
                )
                MiniMetricCard(
                    title: "This Year",
                    value: "\(stats.flightsThisYear)",
                    subtitle: "flights",
                    color: .soraAmber
                )
                MiniMetricCard(
                    title: "Average Trip",
                    value: stats.averageDistanceFormatted,
                    subtitle: "distance",
                    color: Color(red: 0.4, green: 0.85, blue: 0.55)
                )
                MiniMetricCard(
                    title: "Average Time",
                    value: stats.averageDurationFormatted,
                    subtitle: "duration",
                    color: Color(red: 0.7, green: 0.4, blue: 1.0)
                )
            }
        }
    }

    private var flightsByYearChart: some View {
        let labeledYears = Set(yearAxisMarks(for: stats.flightsByYear.map(\.year)))
        return StatsCard(title: "Flights by Year", icon: "calendar") {
            Chart(stats.flightsByYear, id: \.year) { item in
                BarMark(
                    x: .value("Year", String(item.year)),
                    y: .value("Flights", item.count)
                )
                .foregroundStyle(Color.soraAccent.gradient)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let year = value.as(String.self),
                           let yearValue = Int(year),
                           labeledYears.contains(yearValue) {
                            Text(year).font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 160)
        }
    }

    private var cabinClassChart: some View {
        guard !stats.flightsByCabin.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            StatsCard(title: "By Cabin Class", icon: "seat.fill") {
                HStack(spacing: 20) {
                    Chart(stats.flightsByCabin, id: \.cabin) { item in
                        SectorMark(
                            angle: .value("Flights", item.count),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(item.cabin.badgeColor)
                        .cornerRadius(4)
                    }
                    .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(stats.flightsByCabin, id: \.cabin) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.cabin.badgeColor)
                                    .frame(width: 8, height: 8)
                                Text(item.cabin.displayName)
                                    .font(.caption)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        )
    }

    private var milesByYearChart: some View {
        guard !stats.milesByYear.isEmpty else { return AnyView(EmptyView()) }
        let distanceUnit = DistanceUnit.current
        let labeledYears = Set(yearAxisMarks(for: stats.milesByYear.map(\.year)))
        return AnyView(
            StatsCard(title: "\(distanceUnit.displayName) by Year", icon: "ruler") {
                Chart(stats.milesByYear, id: \.year) { item in
                    LineMark(
                        x: .value("Year", String(item.year)),
                        y: .value(distanceUnit.displayName, distanceUnit.value(fromMiles: item.miles))
                    )
                    .foregroundStyle(Color.soraAmber)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    AreaMark(
                        x: .value("Year", String(item.year)),
                        y: .value(distanceUnit.displayName, distanceUnit.value(fromMiles: item.miles))
                    )
                    .foregroundStyle(Color.soraAmber.opacity(0.15).gradient)
                    PointMark(
                        x: .value("Year", String(item.year)),
                        y: .value(distanceUnit.displayName, distanceUnit.value(fromMiles: item.miles))
                    )
                    .foregroundStyle(Color.soraAmber)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let year = value.as(String.self),
                               let yearValue = Int(year),
                               labeledYears.contains(yearValue) {
                                Text(year).font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 140)
            }
        )
    }

    // MARK: List cards

    private var countriesCard: some View {
        StatsCard(title: "Countries Visited", icon: "globe", badge: "\(stats.countriesVisited.count)") {
            let pairs = stats.countriesVisited.map { ($0, countryFlag($0)) }
            FlowLayout(spacing: 8) {
                ForEach(pairs, id: \.0) { country, flag in
                    Text("\(flag) \(country)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.soraNavy)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var airlinesCard: some View {
        StatsCard(title: "Airlines Flown", icon: "airplane.circle", badge: "\(stats.airlinesFlown.count)") {
            VStack(spacing: 6) {
                ForEach(stats.airlinesFlown.prefix(8), id: \.airline) { item in
                    HStack {
                        Text(item.airline.isEmpty ? "Unknown" : item.airline)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count) flight\(item.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var aircraftCard: some View {
        StatsCard(title: "Aircraft Types", icon: "paperplane", badge: "\(stats.aircraftTypesFlown.count)") {
            VStack(spacing: 6) {
                ForEach(stats.aircraftTypesFlown.prefix(8), id: \.type) { item in
                    HStack {
                        Text(item.type.isEmpty ? "Unknown" : item.type)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count)×")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var recordsCard: some View {
        StatsCard(title: "Records", icon: "trophy") {
            VStack(spacing: 12) {
                if let longest = stats.longestFlight {
                    RecordRow(
                        label: "Longest Flight",
                        value: longest.durationFormatted,
                        detail: longest.routeString,
                        icon: "arrow.up.right",
                        color: .soraAccent
                    )
                }
                if let shortest = stats.shortestFlight {
                    RecordRow(
                        label: "Shortest Flight",
                        value: shortest.durationFormatted,
                        detail: shortest.routeString,
                        icon: "arrow.down.right",
                        color: .soraAmber
                    )
                }
                if let longestByDistance = stats.longestByDistance {
                    RecordRow(
                        label: "Longest Distance",
                        value: longestByDistance.distanceFormatted,
                        detail: longestByDistance.routeString,
                        icon: "ruler",
                        color: Color(red: 0.7, green: 0.4, blue: 1.0)
                    )
                }
                if let (airport, count) = stats.mostVisitedAirport {
                    RecordRow(
                        label: "Most Visited Airport",
                        value: airport.iataCode,
                        detail: "\(count) visits • \(airport.city)",
                        icon: "building.2",
                        color: Color(red: 0.4, green: 0.85, blue: 0.55)
                    )
                }
                if let route = stats.mostFlownRoute {
                    RecordRow(
                        label: "Most Flown Route",
                        value: "\(route.departure.iataCode)–\(route.arrival.iataCode)",
                        detail: "\(route.count) times",
                        icon: "arrow.left.and.right",
                        color: .soraAccent
                    )
                }
            }
        }
    }

    // MARK: Helpers

    private func countryFlag(_ countryCode: String) -> String {
        let base: UInt32 = 127397
        var emoji = ""
        for c in countryCode.uppercased().unicodeScalars {
            if let scalar = Unicode.Scalar(base + c.value) {
                emoji.append(Character(scalar))
            }
        }
        return emoji.isEmpty ? "🌍" : emoji
    }

    private func yearAxisMarks(for years: [Int]) -> [Int] {
        let sortedYears = years.sorted()
        guard sortedYears.count > 6 else { return sortedYears }

        let stride = max(1, Int(ceil(Double(sortedYears.count) / 6.0)))
        return sortedYears.enumerated().compactMap { index, year in
            index.isMultiple(of: stride) || index == sortedYears.count - 1 ? year : nil
        }
    }
}

// MARK: - Subviews

private struct MiniMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.soraNavy.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct BigStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.soraCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct StatsCard<Content: View>: View {
    let title: String
    let icon: String
    var badge: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.soraAccent.opacity(0.2))
                        .foregroundStyle(.soraAccent)
                        .clipShape(Capsule())
                }
            }
            content()
        }
        .padding(16)
        .background(Color.soraCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RecordRow: View {
    let label: String
    let value: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.flightCode(15, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

// Simple flow layout for country tags
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
