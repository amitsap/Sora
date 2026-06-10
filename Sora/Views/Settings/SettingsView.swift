import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AeroDataBoxService.self) private var aeroDataBox
    @Environment(OpenSkyService.self) private var openSky
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]
    @Environment(\.modelContext) private var modelContext

    @State private var apiKeyInput = ""
    @State private var showingAPIKey = false
    @State private var openSkyClientIDInput = ""
    @State private var openSkyClientSecretInput = ""
    @State private var showingOpenSkyCredentials = false
    @State private var distanceUnit: DistanceUnit = .miles
    @State private var showingDeleteConfirm = false
    @State private var exportURL: URL?
    @State private var showingExport = false
    @State private var showingImportPicker = false
    @State private var importResult: FlightyImportResult?
    @State private var showingImportResult = false
    @State private var isImporting = false

    private var stats: FlightStats { FlightStats(flights: flights) }

    var body: some View {
        NavigationStack {
            Form {
                statsSection
                apiKeySection
                openSkySection
                displaySection
                dataSection
                dangerSection
                appInfoSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.soraNavy.ignoresSafeArea())
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete all \(flights.count) flights?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete All Flights", role: .destructive) {
                    for flight in flights { modelContext.delete(flight) }
                }
            } message: {
                Text("This cannot be undone.")
            }
            .sheet(isPresented: $showingExport) {
                if let url = exportURL { ShareSheet(url: url) }
            }
            .sheet(isPresented: $showingImportPicker) {
                CSVDocumentPicker { url in importFlights(from: url) }
            }
            .alert("Import Complete", isPresented: $showingImportResult, presenting: importResult) { _ in
                Button("OK") {}
            } message: { result in
                Text(importSummary(result))
            }
            .onAppear {
                distanceUnit = DistanceUnit(
                    rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? "miles"
                ) ?? .miles
                openSkyClientIDInput = openSky.clientID
                openSkyClientSecretInput = openSky.clientSecret
            }
            .onChange(of: distanceUnit) { _, unit in
                UserDefaults.standard.set(unit.rawValue, forKey: "distanceUnit")
            }
        }
    }

    // MARK: - Sections

    private var statsSection: some View {
        let distanceUnit = DistanceUnit.current
        return Section {
            HStack {
                StatPill(value: "\(stats.totalFlights)", label: "Flights")
                StatPill(value: stats.totalMilesFormatted, label: distanceUnit.displayName)
                StatPill(value: stats.totalDaysFormatted, label: "Days")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 4)
        }
    }

    private var apiKeySection: some View {
        Section {
            APIKeyRow(
                hasKey: aeroDataBox.hasAPIKey,
                showingInput: showingAPIKey,
                keyInput: $apiKeyInput,
                onSave: saveAPIKey,
                onEdit: { apiKeyInput = aeroDataBox.apiKey; showingAPIKey = true }
            )
            if !aeroDataBox.hasAPIKey {
                Text("Add your RapidAPI key for AeroDataBox to enable automatic flight lookup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("AeroDataBox API")
        }
        .listRowBackground(Color.soraCard)
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Distance Unit", selection: $distanceUnit) {
                Text("Miles").tag(DistanceUnit.miles)
                Text("Kilometers").tag(DistanceUnit.kilometers)
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.soraCard)
    }

    private var openSkySection: some View {
        Section {
            OpenSkyCredentialsRow(
                hasCredentials: openSky.hasCredentials,
                showingInput: showingOpenSkyCredentials,
                clientIDInput: $openSkyClientIDInput,
                clientSecretInput: $openSkyClientSecretInput,
                onSave: saveOpenSkyCredentials,
                onEdit: {
                    openSkyClientIDInput = openSky.clientID
                    openSkyClientSecretInput = openSky.clientSecret
                    showingOpenSkyCredentials = true
                }
            )
            Text("OpenSky powers the live aircraft overlay on the map. For personal use, create OAuth client credentials in your OpenSky account and paste them here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("OpenSky Live Traffic")
        }
        .listRowBackground(Color.soraCard)
    }

    private var dataSection: some View {
        Section("Data") {
            Button(action: { showingImportPicker = true }) {
                HStack {
                    Label("Import from Flighty CSV", systemImage: "square.and.arrow.down")
                        .foregroundStyle(Color.soraAccent)
                    Spacer()
                    if isImporting { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(isImporting)

            Button(action: exportCSV) {
                Label("Export Logbook as CSV", systemImage: "square.and.arrow.up")
                    .foregroundStyle(Color.soraAccent)
            }
            .disabled(flights.isEmpty)
        }
        .listRowBackground(Color.soraCard)
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete All Flights", systemImage: "trash")
            }
            .disabled(flights.isEmpty)
        }
        .listRowBackground(Color.soraCard)
    }

    private var appInfoSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return Section {
            HStack { Text("Version"); Spacer(); Text(version).foregroundStyle(.secondary) }
            HStack { Text("Build");   Spacer(); Text(build).foregroundStyle(.secondary) }
        }
        .listRowBackground(Color.soraCard)
    }

    // MARK: - Actions

    private func importFlights(from url: URL) {
        isImporting = true
        let context = modelContext
        Task {
            let result = (try? FlightyImportService.importCSV(url: url, into: context))
                ?? FlightyImportResult(imported: 0, skipped: 0, unknownAirports: [])
            importResult = result
            showingImportResult = true
            isImporting = false
        }
    }

    private func saveAPIKey() {
        aeroDataBox.apiKey = apiKeyInput.trimmingCharacters(in: .whitespaces)
        showingAPIKey = false
    }

    private func saveOpenSkyCredentials() {
        openSky.clientID = openSkyClientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        openSky.clientSecret = openSkyClientSecretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        showingOpenSkyCredentials = false
    }

    private func exportCSV() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.timeZone = TimeZone(abbreviation: "UTC")
        var csv = "flight_number,airline,departure,arrival,departure_date,arrival_date,duration_hours,distance_miles,aircraft_type,registration,cabin_class,seat,notes\n"
        for flight in flights {
            let row = [
                flight.flightNumber, flight.airline,
                flight.departureAirport.iataCode, flight.arrivalAirport.iataCode,
                df.string(from: flight.departureDate), df.string(from: flight.arrivalDate),
                String(format: "%.2f", flight.duration / 3600),
                String(format: "%.0f", flight.distanceMiles),
                flight.aircraftType, flight.aircraftRegistration ?? "",
                flight.cabinClass.displayName, flight.seatNumber ?? "",
                (flight.notes ?? "").replacingOccurrences(of: ",", with: ";")
            ].map { "\"\($0)\"" }.joined(separator: ",")
            csv += row + "\n"
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sora_logbook.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        exportURL = tempURL
        showingExport = true
    }

    private func importSummary(_ result: FlightyImportResult) -> String {
        var msg = "\(result.imported) flight\(result.imported == 1 ? "" : "s") imported."
        if result.skipped > 0 {
            msg += " \(result.skipped) skipped (canceled or invalid)."
        }
        if !result.unknownAirports.isEmpty {
            msg += "\n\nAirports without coordinates (map arcs won't show): \(result.unknownAirports.joined(separator: ", "))"
        }
        return msg
    }
}

// MARK: - Supporting types & views

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.soraCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct APIKeyRow: View {
    let hasKey: Bool
    let showingInput: Bool
    @Binding var keyInput: String
    let onSave: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(hasKey ? Color.soraAccent : Color.secondary)
                .frame(width: 24)
            if showingInput {
                TextField("Paste API key", text: $keyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { onSave() }
            } else {
                Text(hasKey ? "API key configured" : "No API key")
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Button(showingInput ? "Save" : "Edit") {
                showingInput ? onSave() : onEdit()
            }
            .font(.caption.bold())
            .foregroundStyle(Color.soraAccent)
        }
    }
}

private struct OpenSkyCredentialsRow: View {
    let hasCredentials: Bool
    let showingInput: Bool
    @Binding var clientIDInput: String
    @Binding var clientSecretInput: String
    let onSave: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "airplane.circle.fill")
                    .foregroundStyle(hasCredentials ? Color.soraAccent : Color.secondary)
                    .frame(width: 24)

                if showingInput {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Client ID", text: $clientIDInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("Client Secret", text: $clientSecretInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } else {
                    Text(hasCredentials ? "OpenSky credentials configured" : "No OpenSky credentials")
                        .foregroundStyle(Color.secondary)
                }

                Spacer()

                Button(showingInput ? "Save" : "Edit") {
                    showingInput ? onSave() : onEdit()
                }
                .font(.caption.bold())
                .foregroundStyle(Color.soraAccent)
            }
        }
    }
}

private struct CSVDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.commaSeparatedText, .plainText])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tmp)
            if (try? FileManager.default.copyItem(at: url, to: tmp)) != nil {
                onPick(tmp)
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
