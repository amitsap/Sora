import SwiftUI
import SwiftData

struct LogbookView: View {
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var showingAddFlight = false
    @State private var showingFilter = false
    @State private var filterCabin: CabinClass?
    @State private var filterAirline = ""
    @State private var selectedYear: Int?

    private var availableYears: [Int] {
        let calendar = Calendar.current
        return Array(Set(flights.map { calendar.component(.year, from: $0.departureDate) }))
            .sorted(by: >)
    }

    private var filtered: [Flight] {
        flights.filter { flight in
            let flightYear = Calendar.current.component(.year, from: flight.departureDate)
            let matchesSearch = searchText.isEmpty
                || flight.flightNumber.localizedCaseInsensitiveContains(searchText)
                || flight.airline.localizedCaseInsensitiveContains(searchText)
                || flight.departureAirport.iataCode.localizedCaseInsensitiveContains(searchText)
                || flight.arrivalAirport.iataCode.localizedCaseInsensitiveContains(searchText)
                || flight.departureAirport.city.localizedCaseInsensitiveContains(searchText)
                || flight.arrivalAirport.city.localizedCaseInsensitiveContains(searchText)
            let matchesCabin = filterCabin == nil || flight.cabinClass == filterCabin
            let matchesAirline = filterAirline.isEmpty
                || flight.airline.localizedCaseInsensitiveContains(filterAirline)
            let matchesYear = selectedYear == nil || flightYear == selectedYear
            return matchesSearch && matchesCabin && matchesAirline && matchesYear
        }
    }

    private var upcomingFlights: [Flight] {
        filtered
            .filter { $0.isUpcoming }
            .sorted { $0.departureDate < $1.departureDate }
    }

    private var loggedFlights: [Flight] {
        filtered
            .filter { !$0.isUpcoming }
            .sorted { $0.departureDate > $1.departureDate }
    }

    // Group by year, newest first
    private var byYear: [(year: Int, flights: [Flight])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: loggedFlights) {
            calendar.component(.year, from: $0.departureDate)
        }
        return groups.map { ($0.key, $0.value) }
            .sorted { $0.year > $1.year }
    }

    private var hasActiveFilters: Bool {
        filterCabin != nil || !filterAirline.isEmpty || selectedYear != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if flights.isEmpty {
                    EmptyLogbookView(onAdd: { showingAddFlight = true })
                } else {
                    YearFilterBar(years: availableYears, selectedYear: $selectedYear)
                        .padding(.top, 8)

                    List {
                        if !upcomingFlights.isEmpty {
                            Section {
                                ForEach(upcomingFlights) { flight in
                                    NavigationLink(destination: FlightDetailView(flight: flight)) {
                                        FlightRowView(flight: flight)
                                    }
                                    .listRowBackground(Color.soraCard)
                                }
                                .onDelete { offsets in deleteFlight(from: upcomingFlights, at: offsets) }
                            } header: {
                                UpcomingHeader(count: upcomingFlights.count)
                            }
                        }

                        ForEach(byYear, id: \.year) { group in
                            Section {
                                ForEach(group.flights) { flight in
                                    NavigationLink(destination: FlightDetailView(flight: flight)) {
                                        FlightRowView(flight: flight)
                                    }
                                    .listRowBackground(Color.soraCard)
                                }
                                .onDelete { offsets in deleteFlight(from: group.flights, at: offsets) }
                            } header: {
                                YearHeader(year: group.year, count: group.flights.count)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.soraNavy.ignoresSafeArea())
            .navigationTitle("Logbook")
            .searchable(text: $searchText, prompt: "Flight, airline, airport…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingFilter = true }) {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(hasActiveFilters ? .soraAccent : .primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddFlight = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddFlight) {
                AddFlightView()
            }
            .sheet(isPresented: $showingFilter) {
                FilterSheet(
                    filterCabin: $filterCabin,
                    filterAirline: $filterAirline,
                    selectedYear: $selectedYear
                )
            }
        }
    }

    private func deleteFlight(from group: [Flight], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(group[index])
        }
    }
}

// MARK: - Subviews

private struct YearHeader: View {
    let year: Int
    let count: Int

    var body: some View {
        HStack {
            Text(String(year))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count) FLIGHT\(count == 1 ? "" : "S")")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UpcomingHeader: View {
    let count: Int

    var body: some View {
        HStack {
            Text("Upcoming")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count) FLIGHT\(count == 1 ? "" : "S")")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyLogbookView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 72))
                .foregroundStyle(.soraAccent.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Flights Yet")
                    .font(.title2.bold())
                Text("Log your first flight to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAdd) {
                Label("Add Flight", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.soraAccent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(40)
    }
}

private struct FilterSheet: View {
    @Binding var filterCabin: CabinClass?
    @Binding var filterAirline: String
    @Binding var selectedYear: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Cabin Class") {
                    Button("All Classes") {
                        filterCabin = nil
                    }
                    .foregroundStyle(filterCabin == nil ? .soraAccent : .primary)

                    ForEach(CabinClass.allCases, id: \.self) { cabin in
                        Button(action: { filterCabin = cabin }) {
                            HStack {
                                Text(cabin.displayName)
                                Spacer()
                                if filterCabin == cabin {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.soraAccent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .listRowBackground(Color.soraCard)

                Section("Airline") {
                    TextField("Filter by airline…", text: $filterAirline)
                }
                .listRowBackground(Color.soraCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.soraNavy.ignoresSafeArea())
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        filterCabin = nil
                        filterAirline = ""
                        selectedYear = nil
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }
}

private struct YearFilterBar: View {
    let years: [Int]
    @Binding var selectedYear: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                YearFilterChip(
                    title: "All",
                    isSelected: selectedYear == nil,
                    action: { selectedYear = nil }
                )

                ForEach(years, id: \.self) { year in
                    YearFilterChip(
                        title: String(year),
                        isSelected: selectedYear == year,
                        action: { selectedYear = year }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

private struct YearFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.soraAccent : Color.soraCard)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
