import SwiftUI
import SwiftData
import Photos
import MapKit
import CoreLocation

struct FlightDetailView: View {
    @Environment(AeroDataBoxService.self) private var aeroDataBox
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let flight: Flight

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var selectedPhotoID: PhotoIdentifier?
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var upcomingStatus: UpcomingFlightStatus?
    @State private var upcomingStatusError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero map with route arc
                MiniRouteMap(
                    departure: flight.departureAirport,
                    arrival: flight.arrivalAirport
                )
                .frame(height: 240)
                .clipped()

                VStack(alignment: .leading, spacing: 24) {
                    // Flight header
                    flightHeader

                    Divider().background(Color.white.opacity(0.1))

                    // Route detail
                    routeSection

                    Divider().background(Color.white.opacity(0.1))

                    // Times & stats
                    statsSection

                    Divider().background(Color.white.opacity(0.1))

                    // Aircraft
                    aircraftSection

                    if shouldShowUpcomingStatus {
                        Divider().background(Color.white.opacity(0.1))
                        upcomingStatusSection
                    }

                    // Photos
                    if !flight.photoAssetIdentifiers.isEmpty {
                        Divider().background(Color.white.opacity(0.1))
                        photosSection
                    }

                    // Notes
                    if let notes = flight.notes, !notes.isEmpty {
                        Divider().background(Color.white.opacity(0.1))
                        notesSection(notes)
                    }
                }
                .padding(20)
            }
        }
        .background(Color.soraNavy.ignoresSafeArea())
        .navigationTitle(flight.routeString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showingEdit = true }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: { showingDeleteConfirm = true }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddFlightView(existingFlight: flight)
        }
        .confirmationDialog("Delete this flight?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Flight", role: .destructive) {
                modelContext.delete(flight)
                dismiss()
            }
        }
        .sheet(item: $selectedPhotoID) { item in
            FullScreenPhotoView(identifier: item.id, allIdentifiers: flight.photoAssetIdentifiers)
        }
        .task {
            await loadPhotos()
            await loadUpcomingStatusIfNeeded()
        }
    }

    // MARK: Sections

    private var flightHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(flight.formattedFlightNumber)
                .font(.flightCode(28, weight: .bold))
                .foregroundStyle(.soraAccent)

            HStack(spacing: 8) {
                if !flight.airline.isEmpty {
                    Text(flight.airline)
                        .font(.headline)
                }
                CabinBadge(cabin: flight.cabinClass)
                if !flight.isCompleted {
                    Text("Upcoming")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.soraAmber.opacity(0.2))
                        .foregroundStyle(.soraAmber)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var routeSection: some View {
        HStack(alignment: .top, spacing: 0) {
            // Departure
            VStack(alignment: .leading, spacing: 4) {
                Text(flight.departureAirport.iataCode)
                    .font(.flightCode(32, weight: .bold))
                Text(flight.departureAirport.city)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(flight.departureAirport.name)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Arrow
            VStack(spacing: 4) {
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundStyle(.soraAccent)
                    .padding(.top, 6)
                Rectangle()
                    .fill(Color.soraAccent.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 4)
            }
            .frame(width: 60)

            // Arrival
            VStack(alignment: .trailing, spacing: 4) {
                Text(flight.arrivalAirport.iataCode)
                    .font(.flightCode(32, weight: .bold))
                Text(flight.arrivalAirport.city)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(flight.arrivalAirport.name)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var statsSection: some View {
        let cols: [(String, String, String)] = [
            ("Date", flight.departureDate.formatted(date: .abbreviated, time: .omitted), "calendar"),
            ("Duration", flight.durationFormatted, "clock"),
            ("Distance", flight.distanceFormatted, "ruler"),
        ]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(cols, id: \.0) { label, value, icon in
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.soraAccent)
                    Text(value)
                        .font(.subheadline.bold())
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.soraCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var aircraftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Aircraft", systemImage: "paperplane")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !flight.aircraftType.isEmpty {
                DetailRow(label: "Type", value: flight.aircraftType)
            }
            if let reg = flight.aircraftRegistration, !reg.isEmpty {
                DetailRow(label: "Registration", value: reg, monospaced: true)
            }
            if let seat = flight.seatNumber, !seat.isEmpty {
                DetailRow(label: "Seat", value: seat, monospaced: true)
            }
        }
    }

    private var upcomingStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Upcoming Status", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let upcomingStatus {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(upcomingStatus.statusText)
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.soraAccent.opacity(0.18))
                            .foregroundStyle(.soraAccent)
                            .clipShape(Capsule())
                        Spacer()
                        Text(statusSummaryText(for: upcomingStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let departure = upcomingStatus.effectiveDeparture,
                       let arrival = upcomingStatus.effectiveArrival {
                        FlightProgressRow(
                            now: Date(),
                            departure: departure,
                            arrival: arrival
                        )
                    }

                    VStack(spacing: 10) {
                        if let departureLine = airportStatusLine(
                            title: "Departure",
                            time: upcomingStatus.effectiveDeparture,
                            terminal: upcomingStatus.departureTerminal,
                            gate: upcomingStatus.departureGate
                        ) {
                            DetailRow(label: departureLine.label, value: departureLine.value)
                        }

                        if let arrivalLine = airportStatusLine(
                            title: "Arrival",
                            time: upcomingStatus.effectiveArrival,
                            terminal: upcomingStatus.arrivalTerminal,
                            gate: upcomingStatus.arrivalGate
                        ) {
                            DetailRow(label: arrivalLine.label, value: arrivalLine.value)
                        }

                        if let aircraft = upcomingStatus.aircraftType, !aircraft.isEmpty {
                            DetailRow(label: "Assigned Aircraft", value: aircraft)
                        }
                        if let registration = upcomingStatus.aircraftRegistration, !registration.isEmpty {
                            DetailRow(label: "Tail Number", value: registration, monospaced: true)
                        } else {
                            DetailRow(label: "Tail Number", value: "Not assigned yet")
                        }
                    }
                }
                .padding(14)
                .background(Color.soraCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if let upcomingStatusError {
                Text(upcomingStatusError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .tint(.soraAccent)
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Photos", systemImage: "photo.on.rectangle")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(flight.photoAssetIdentifiers, id: \.self) { identifier in
                    Button(action: { selectedPhotoID = PhotoIdentifier(id: identifier) }) {
                        if let img = loadedImages[identifier] {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.soraCard)
                                .aspectRatio(1, contentMode: .fill)
                                .overlay(
                                    ProgressView().scaleEffect(0.7)
                                )
                        }
                    }
                }
            }
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(notes)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    // MARK: Photo loading

    private var shouldShowUpcomingStatus: Bool {
        !flight.isCompleted || flight.departureDate > Date().addingTimeInterval(-6 * 3600)
    }

    private func loadUpcomingStatusIfNeeded() async {
        guard shouldShowUpcomingStatus, aeroDataBox.hasAPIKey else { return }

        do {
            upcomingStatus = try await aeroDataBox.lookupUpcomingStatus(
                flightNumber: flight.flightNumber,
                date: flight.departureDate
            )
        } catch {
            upcomingStatusError = error.localizedDescription
        }
    }

    private func airportStatusLine(title: String, time: Date?, terminal: String?, gate: String?) -> (label: String, value: String)? {
        guard time != nil || terminal != nil || gate != nil else { return nil }

        var pieces: [String] = []
        if let time {
            pieces.append(time.formatted(date: .omitted, time: .shortened))
        }
        if let terminal {
            pieces.append("T\(terminal)")
        }
        if let gate {
            pieces.append("G\(gate)")
        }
        return (title, pieces.joined(separator: " • "))
    }

    private func statusSummaryText(for status: UpcomingFlightStatus) -> String {
        guard let departure = status.effectiveDeparture else { return "Awaiting update" }

        let now = Date()
        if now < departure {
            return "Departs in \(FlightTimeFormatting.countdownString(until: departure, relativeTo: now))"
        }

        if let arrival = status.effectiveArrival, now < arrival {
            return "Currently in progress"
        }

        return "Latest operational update"
    }

    private func loadPhotos() async {
        let identifiers = flight.photoAssetIdentifiers
        guard !identifiers.isEmpty else { return }

        let results = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic

        results.enumerateObjects { asset, _, _ in
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image {
                    Task { @MainActor in
                        loadedImages[asset.localIdentifier] = image
                    }
                }
            }
        }
    }
}

private struct FlightProgressRow: View {
    let now: Date
    let departure: Date
    let arrival: Date

    private var progress: Double {
        let total = arrival.timeIntervalSince(departure)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(departure)
        return min(max(elapsed / total, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.soraAccent, .soraAmber],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)

            HStack {
                Text(departure.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(arrival.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mini Map

/// Non-interactive mini map showing the flight route arc.
struct MiniRouteMap: UIViewRepresentable {
    let departure: Airport
    let arrival: Airport

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.overrideUserInterfaceStyle = .dark
        map.delegate = context.coordinator
        if #available(iOS 16.0, *) {
            let config = MKImageryMapConfiguration(elevationStyle: .realistic)
            map.preferredConfiguration = config
        } else {
            map.mapType = .satelliteFlyover
        }
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        let points = greatCirclePoints(from: departure.coordinate, to: arrival.coordinate, steps: 80)
        var coords = points
        let polyline = MKPolyline(coordinates: &coords, count: coords.count)
        mapView.addOverlay(polyline)

        // Airport pins
        let depPin = MKPointAnnotation()
        depPin.coordinate = departure.coordinate
        depPin.title = departure.iataCode
        let arrPin = MKPointAnnotation()
        arrPin.coordinate = arrival.coordinate
        arrPin.title = arrival.iataCode
        mapView.addAnnotations([depPin, arrPin])

        // Fit region
        let allCoords = [departure.coordinate, arrival.coordinate] + points
        fitMap(mapView, to: allCoords)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func fitMap(_ mapView: MKMapView, to coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        var rect = MKMapRect.null
        for coord in coords {
            let point = MKMapPoint(coord)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            rect = rect.isNull ? pointRect : rect.union(pointRect)
        }

        guard !rect.isNull else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.1)
        mapView.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: 40, left: 28, bottom: 40, right: 28),
            animated: false
        )
        CATransaction.commit()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.58, green: 0.86, blue: 1.0, alpha: 0.82)
                renderer.lineWidth = 3.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let id = "detailAirport"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = false
            for subview in view.subviews {
                subview.removeFromSuperview()
            }

            let glow = UIView(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
            glow.backgroundColor = UIColor(red: 0.58, green: 0.86, blue: 1.0, alpha: 0.24)
            glow.layer.cornerRadius = 9

            let dot = UIView(frame: CGRect(x: 5, y: 5, width: 8, height: 8))
            dot.backgroundColor = UIColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 0.98)
            dot.layer.cornerRadius = 4

            view.addSubview(glow)
            view.addSubview(dot)
            view.frame = glow.frame
            return view
        }
    }
}

// MARK: - Helpers

private struct DetailRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .flightCode(15) : .body)
        }
    }
}

private struct PhotoIdentifier: Identifiable {
    let id: String
}

private struct FullScreenPhotoView: View {
    let identifier: String
    let allIdentifiers: [String]
    @State private var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task { await loadImage() }
        .onTapGesture { dismiss() }
    }

    private func loadImage() async {
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = results.firstObject else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        manager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { img, _ in
            Task { @MainActor in self.image = img }
        }
    }
}
