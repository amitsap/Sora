import SwiftUI
import SwiftData
import PhotosUI

struct FlightDraft: Identifiable, Equatable {
    let id = UUID()
    let flightNumber: String
    let departureDate: Date

    static let empty = FlightDraft(flightNumber: "", departureDate: .now)

    private static let deepLinkDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    init(flightNumber: String, departureDate: Date) {
        self.flightNumber = flightNumber
        self.departureDate = departureDate
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "sora" else { return nil }

        let destination = url.host ?? url.pathComponents.dropFirst().first ?? ""
        guard destination == "add-flight" else { return nil }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = Dictionary(uniqueKeysWithValues: components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
        guard let flightNumber = items["flightNumber"], !flightNumber.isEmpty else { return nil }

        let departureDate: Date
        if let rawDate = items["date"], let parsedDate = Self.deepLinkDateFormatter.date(from: rawDate) {
            departureDate = parsedDate
        } else {
            departureDate = .now
        }

        self.init(flightNumber: flightNumber.uppercased(), departureDate: departureDate)
    }
}

struct AddFlightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AeroDataBoxService.self) private var aeroDataBox

    // If non-nil, we're editing an existing flight
    var existingFlight: Flight?
    var prefill: FlightDraft? = nil

    // Form state
    @State private var flightNumber = ""
    @State private var airline = ""
    @State private var aircraftType = ""
    @State private var aircraftRegistration = ""
    @State private var departureAirport: Airport?
    @State private var arrivalAirport: Airport?
    @State private var departureDate = Date()
    @State private var arrivalDate = Date().addingTimeInterval(7200)
    @State private var distanceMiles = 0.0
    @State private var cabinClass: CabinClass = .economy
    @State private var seatNumber = ""
    @State private var notes = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photoAssetIdentifiers: [String] = []
    @State private var isCompleted = true

    // UI state
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var showingDepartureSearch = false
    @State private var showingArrivalSearch = false
    @State private var showingLookupError = false
    @State private var didPopulateInitialState = false

    private var isEditing: Bool { existingFlight != nil }

    var body: some View {
        NavigationStack {
            Form {
                // Flight number + lookup
                Section {
                    HStack(spacing: 12) {
                        TextField("Flight number", text: $flightNumber)
                            .font(.flightCode(17, weight: .bold))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

                        if isLookingUp {
                            ProgressView()
                                .scaleEffect(0.85)
                        } else {
                            Button(action: lookupFlight) {
                                Label("Look Up", systemImage: "magnifyingglass")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.soraAccent)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .disabled(flightNumber.isEmpty)
                        }
                    }

                    if let lookupError {
                        Text(lookupError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    DatePicker("Date", selection: $departureDate, displayedComponents: .date)
                }
                .listRowBackground(Color.soraCard)

                // Airports
                Section("Route") {
                    Button(action: { showingDepartureSearch = true }) {
                        AirportPickerRow(
                            label: "Departure",
                            airport: departureAirport,
                            icon: "airplane.departure"
                        )
                    }

                    Button(action: { showingArrivalSearch = true }) {
                        AirportPickerRow(
                            label: "Arrival",
                            airport: arrivalAirport,
                            icon: "airplane.arrival"
                        )
                    }
                }
                .listRowBackground(Color.soraCard)

                // Times
                Section("Times") {
                    DatePicker("Departure", selection: $departureDate, displayedComponents: .hourAndMinute)
                        .onChange(of: departureDate) { _, _ in recalculateDistance() }
                    DatePicker("Arrival", selection: $arrivalDate, displayedComponents: .hourAndMinute)
                    HStack {
                        Text("Duration")
                            .foregroundStyle(.secondary)
                        Spacer()
                        let dur = max(0, arrivalDate.timeIntervalSince(departureDate))
                        let h = Int(dur) / 3600
                        let m = Int(dur) % 3600 / 60
                        Text("\(h)h \(m)m")
                            .font(.flightCode(15))
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.soraCard)

                // Airline & aircraft
                Section("Aircraft") {
                    TextField("Airline", text: $airline)
                    TextField("Aircraft type (e.g. Boeing 737-800)", text: $aircraftType)
                    TextField("Registration (e.g. N12345)", text: $aircraftRegistration)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .listRowBackground(Color.soraCard)

                // Distance
                Section("Distance") {
                    HStack {
                        TextField("Miles", value: $distanceMiles, format: .number)
                            .keyboardType(.decimalPad)
                        Text("mi")
                            .foregroundStyle(.secondary)
                        if departureAirport != nil && arrivalAirport != nil {
                            Button("Calculate") { recalculateDistance() }
                                .font(.caption)
                                .foregroundStyle(.soraAccent)
                        }
                    }
                }
                .listRowBackground(Color.soraCard)

                // Cabin
                Section("Cabin") {
                    Picker("Class", selection: $cabinClass) {
                        ForEach(CabinClass.allCases, id: \.self) { cabin in
                            Text(cabin.displayName).tag(cabin)
                        }
                    }
                    TextField("Seat (e.g. 14A)", text: $seatNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .listRowBackground(Color.soraCard)

                // Notes
                Section("Notes") {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: false)
                }
                .listRowBackground(Color.soraCard)

                // Photos
                Section("Photos") {
                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 20, matching: .images) {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                            .foregroundStyle(.soraAccent)
                    }
                    if !photoAssetIdentifiers.isEmpty {
                        Text("\(photoAssetIdentifiers.count) photo\(photoAssetIdentifiers.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.soraCard)

                // Status
                Section {
                    Toggle("Mark as completed", isOn: $isCompleted)
                }
                .listRowBackground(Color.soraCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.soraNavy.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Flight" : "Add Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveFlight() }
                        .disabled(!isFormValid)
                        .bold()
                }
            }
            .sheet(isPresented: $showingDepartureSearch) {
                AirportSearchView(title: "Departure Airport") { airport in
                    departureAirport = airport
                    recalculateDistance()
                }
            }
            .sheet(isPresented: $showingArrivalSearch) {
                AirportSearchView(title: "Arrival Airport") { airport in
                    arrivalAirport = airport
                    recalculateDistance()
                }
            }
            .onChange(of: selectedPhotoItems) { _, items in
                Task { await loadPhotoIdentifiers(from: items) }
            }
            .onAppear { populateInitialState() }
        }
    }

    // MARK: Computed

    private var isFormValid: Bool {
        !flightNumber.isEmpty && departureAirport != nil && arrivalAirport != nil
    }

    // MARK: Actions

    private func lookupFlight() {
        guard !flightNumber.isEmpty else { return }
        isLookingUp = true
        lookupError = nil

        Task {
            do {
                let result = try await aeroDataBox.lookupFlight(
                    flightNumber: flightNumber,
                    date: departureDate
                )
                flightNumber = result.flightNumber
                airline = result.airline
                departureAirport = result.departureAirport
                arrivalAirport = result.arrivalAirport
                departureDate = result.departureDate
                arrivalDate = result.arrivalDate
                aircraftType = result.aircraftType
                aircraftRegistration = result.aircraftRegistration ?? ""
                distanceMiles = result.distanceMiles
            } catch {
                lookupError = error.localizedDescription
            }
            isLookingUp = false
        }
    }

    private func recalculateDistance() {
        guard let dep = departureAirport, let arr = arrivalAirport else { return }
        distanceMiles = haversineDistance(from: dep.coordinate, to: arr.coordinate)
    }

    private func saveFlight() {
        guard let dep = departureAirport, let arr = arrivalAirport else { return }

        if let existing = existingFlight {
            // Update in place
            existing.flightNumber = flightNumber.uppercased()
            existing.airline = airline
            existing.aircraftType = aircraftType
            existing.aircraftRegistration = aircraftRegistration.isEmpty ? nil : aircraftRegistration
            existing.departureAirport = dep
            existing.arrivalAirport = arr
            existing.departureDate = departureDate
            existing.arrivalDate = arrivalDate
            existing.distanceMiles = distanceMiles
            existing.cabinClass = cabinClass
            existing.seatNumber = seatNumber.isEmpty ? nil : seatNumber
            existing.notes = notes.isEmpty ? nil : notes
            existing.photoAssetIdentifiers = photoAssetIdentifiers
            existing.isCompleted = isCompleted
        } else {
            let flight = Flight(
                flightNumber: flightNumber.uppercased(),
                airline: airline,
                aircraftType: aircraftType,
                aircraftRegistration: aircraftRegistration.isEmpty ? nil : aircraftRegistration,
                departureAirport: dep,
                arrivalAirport: arr,
                departureDate: departureDate,
                arrivalDate: arrivalDate,
                distanceMiles: distanceMiles,
                cabinClass: cabinClass,
                seatNumber: seatNumber.isEmpty ? nil : seatNumber,
                notes: notes.isEmpty ? nil : notes,
                photoAssetIdentifiers: photoAssetIdentifiers,
                isCompleted: isCompleted
            )
            modelContext.insert(flight)
        }
        dismiss()
    }

    private func populateInitialState() {
        guard !didPopulateInitialState else { return }
        didPopulateInitialState = true

        if let existingFlight {
            populateFromExisting(existingFlight)
        } else if let prefill {
            populateFromPrefill(prefill)
        }
    }

    private func populateFromPrefill(_ draft: FlightDraft) {
        flightNumber = draft.flightNumber
        departureDate = draft.departureDate
        if arrivalDate <= departureDate {
            arrivalDate = departureDate.addingTimeInterval(7200)
        }
    }

    private func populateFromExisting(_ f: Flight) {
        flightNumber = f.flightNumber
        airline = f.airline
        aircraftType = f.aircraftType
        aircraftRegistration = f.aircraftRegistration ?? ""
        departureAirport = f.departureAirport
        arrivalAirport = f.arrivalAirport
        departureDate = f.departureDate
        arrivalDate = f.arrivalDate
        distanceMiles = f.distanceMiles
        cabinClass = f.cabinClass
        seatNumber = f.seatNumber ?? ""
        notes = f.notes ?? ""
        photoAssetIdentifiers = f.photoAssetIdentifiers
        isCompleted = f.isCompleted
    }

    private func loadPhotoIdentifiers(from items: [PhotosPickerItem]) async {
        // PHAsset identifiers are available via the localIdentifier on PHAsset,
        // but PhotosPickerItem doesn't expose it directly. We store the item's
        // itemIdentifier which is available in iOS 16+.
        photoAssetIdentifiers = items.compactMap { $0.itemIdentifier }
    }
}

// MARK: - Subviews

private struct AirportPickerRow: View {
    let label: String
    let airport: Airport?
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.soraAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let airport {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(airport.iataCode)
                            .font(.flightCode(16, weight: .bold))
                        Text(airport.city.isEmpty ? airport.name : airport.city)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Select airport")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
    }
}
