import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct FullMapView: View {
    @Query(sort: \Flight.departureDate, order: .reverse) private var flights: [Flight]

    @State private var visualStyle: VisualStyle = .flat
    @State private var selectedAirport: AirportAnnotation?
    @State private var showingAirportDetail = false

    enum VisualStyle: String, CaseIterable {
        case flat = "Flat"
        case globe = "Globe"
    }

    var body: some View {
        ZStack(alignment: .top) {
            FullMapRepresentable(
                flights: flights,
                visualStyle: visualStyle,
                onAirportTapped: { annotation in
                    selectedAirport = annotation
                    showingAirportDetail = true
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                ForEach(VisualStyle.allCases, id: \.self) { style in
                    Button(action: { visualStyle = style }) {
                        Image(systemName: style == .flat ? "map" : "globe.americas.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(visualStyle == style ? Color.white : Color.white.opacity(0.72))
                            .frame(width: 40, height: 40)
                            .background(visualStyle == style ? Color.soraAccent : Color.soraCard.opacity(0.94))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
        .sheet(isPresented: $showingAirportDetail) {
            if let airport = selectedAirport {
                AirportDetailSheet(
                    airport: airport.airport,
                    visitCount: visitCount(for: airport.airport),
                    flights: flightsFor(airport: airport.airport)
                )
                .presentationDetents([.medium])
            }
        }
    }

    private func visitCount(for airport: Airport) -> Int {
        flights.reduce(into: 0) { total, flight in
            if flight.departureAirport.iataCode == airport.iataCode {
                total += 1
            }
            if flight.arrivalAirport.iataCode == airport.iataCode {
                total += 1
            }
        }
    }

    private func flightsFor(airport: Airport) -> [Flight] {
        flights.filter {
            $0.departureAirport.iataCode == airport.iataCode ||
            $0.arrivalAirport.iataCode == airport.iataCode
        }
    }
}

// MARK: - Map UIViewRepresentable

struct FullMapRepresentable: UIViewRepresentable {
    let flights: [Flight]
    let visualStyle: FullMapView.VisualStyle
    let onAirportTapped: (AirportAnnotation) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.overrideUserInterfaceStyle = .dark
        map.showsUserLocation = false
        map.delegate = context.coordinator
        applyVisualStyle(visualStyle, to: map, resetCamera: true)
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        context.coordinator.onAirportTapped = onAirportTapped
        if context.coordinator.visualStyle != visualStyle {
            context.coordinator.visualStyle = visualStyle
            applyVisualStyle(visualStyle, to: mapView, resetCamera: true)
        }
        context.coordinator.updateAutoDrift(for: mapView)

        let now = Date()
        let oneYear: TimeInterval = 365 * 24 * 3600

        // Build airport visit counts
        var visitCounts: [String: (Airport, Int)] = [:]
        for flight in flights {
            let dep = flight.departureAirport
            let arr = flight.arrivalAirport
            visitCounts[dep.iataCode] = (dep, (visitCounts[dep.iataCode]?.1 ?? 0) + 1)
            visitCounts[arr.iataCode] = (arr, (visitCounts[arr.iataCode]?.1 ?? 0) + 1)
        }

        for flight in flights {
            var pts = greatCirclePoints(
                from: flight.departureAirport.coordinate,
                to: flight.arrivalAirport.coordinate,
                steps: 80
            )
            guard pts.count > 1 else { continue }
            let polyline = FlightPolyline(coordinates: &pts, count: pts.count)
            let age = now.timeIntervalSince(flight.departureDate)
            polyline.recency = Float(max(0.15, min(1.0, 1.0 - age / oneYear)))
            mapView.addOverlay(polyline)
        }

        for (_, pair) in visitCounts {
            mapView.addAnnotation(AirportAnnotation(airport: pair.0, visitCount: pair.1))
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(onAirportTapped: onAirportTapped)
        coordinator.visualStyle = visualStyle
        return coordinator
    }

    private func applyVisualStyle(_ style: FullMapView.VisualStyle, to mapView: MKMapView, resetCamera: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.2)
        defer { CATransaction.commit() }

        switch style {
        case .flat:
            if #available(iOS 16.0, *) {
                let config = MKStandardMapConfiguration(elevationStyle: .flat)
                config.emphasisStyle = .muted
                mapView.preferredConfiguration = config
            } else {
                mapView.mapType = .mutedStandard
            }

            guard resetCamera else { return }
            mapView.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                    span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 300)
                ),
                animated: false
            )

        case .globe:
            if #available(iOS 16.0, *) {
                let config = MKImageryMapConfiguration(elevationStyle: .realistic)
                mapView.preferredConfiguration = config
            } else {
                mapView.mapType = .satelliteFlyover
            }

            guard resetCamera else { return }
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                fromDistance: 45_000_000,
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onAirportTapped: (AirportAnnotation) -> Void
        var visualStyle: FullMapView.VisualStyle = .flat
        private weak var mapView: MKMapView?
        private var driftTimer: Timer?
        private var driftPhase: Double = 0
        private var resumeDriftWorkItem: DispatchWorkItem?
        private var isUserInteracting = false

        init(onAirportTapped: @escaping (AirportAnnotation) -> Void) {
            self.onAirportTapped = onAirportTapped
        }

        deinit {
            driftTimer?.invalidate()
            resumeDriftWorkItem?.cancel()
        }

        func updateAutoDrift(for mapView: MKMapView) {
            self.mapView = mapView

            let shouldDrift = visualStyle == .globe
            if shouldDrift {
                startAutoDriftIfNeeded()
            } else {
                stopAutoDrift()
            }
        }

        private func startAutoDriftIfNeeded() {
            guard driftTimer == nil, !isUserInteracting else { return }
            driftTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.stepAutoDrift()
            }
            if let driftTimer {
                RunLoop.main.add(driftTimer, forMode: .common)
            }
        }

        private func stopAutoDrift() {
            driftTimer?.invalidate()
            driftTimer = nil
        }

        private func suspendAutoDriftForUserInteraction() {
            isUserInteracting = true
            stopAutoDrift()
            resumeDriftWorkItem?.cancel()
        }

        private func scheduleAutoDriftResume() {
            resumeDriftWorkItem?.cancel()
            guard visualStyle == .globe else { return }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.isUserInteracting = false
                self.startAutoDriftIfNeeded()
            }
            resumeDriftWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
        }

        private func stepAutoDrift() {
            guard let mapView, visualStyle == .globe, !isUserInteracting else { return }

            driftPhase += 0.0035
            let heading = fmod(driftPhase * 180 / .pi, 360)
            let latitude = 18 + sin(driftPhase * 0.7) * 4
            let longitude = fmod((driftPhase * 8).truncatingRemainder(dividingBy: 360) - 180 + 360, 360) - 180

            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                fromDistance: 45_000_000,
                pitch: 0,
                heading: heading
            )
            mapView.setCamera(camera, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? FlightPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            let opacity = CGFloat(polyline.recency)
            switch visualStyle {
            case .flat:
                renderer.strokeColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: opacity)
                renderer.lineWidth = 1.8
            case .globe:
                renderer.strokeColor = UIColor(red: 0.58, green: 0.86, blue: 1.0, alpha: max(0.22, opacity * 0.75))
                renderer.lineWidth = 2.6
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let ann = annotation as? AirportAnnotation {
                let id = "fullAirport"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)) as MKAnnotationView
                view.annotation = annotation

                let size = CGFloat(min(4 + ann.visitCount * 2, 16))
                for sub in view.subviews { sub.removeFromSuperview() }
                view.layer.shadowOpacity = visualStyle == .globe ? 0.9 : 0
                view.layer.shadowRadius = visualStyle == .globe ? 10 : 0
                view.layer.shadowOffset = .zero
                view.layer.shadowColor = UIColor(red: 0.4, green: 0.84, blue: 1.0, alpha: 1).cgColor
                let dot = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
                dot.backgroundColor = visualStyle == .globe
                    ? UIColor(red: 0.58, green: 0.86, blue: 1.0, alpha: 0.92)
                    : UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.85)
                dot.layer.cornerRadius = size / 2
                view.addSubview(dot)
                view.frame = dot.frame
                view.canShowCallout = false
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let ann = annotation as? AirportAnnotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            onAirportTapped(ann)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            suspendAutoDriftForUserInteraction()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            scheduleAutoDriftResume()
        }
    }
}

// MARK: - AirportAnnotation (extended with visitCount)

extension AirportAnnotation {
    convenience init(airport: Airport, visitCount: Int) {
        self.init(airport: airport)
        self.visitCount = visitCount
    }
}

// visitCount stored via associated objects on AirportAnnotation
private nonisolated(unsafe) var visitCountAssocKey: UInt8 = 0
extension AirportAnnotation {
    var visitCount: Int {
        get { objc_getAssociatedObject(self, &visitCountAssocKey) as? Int ?? 1 }
        set { objc_setAssociatedObject(self, &visitCountAssocKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - Airport detail sheet

private struct AirportDetailSheet: View {
    let airport: Airport
    let visitCount: Int
    let flights: [Flight]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(airport.iataCode)
                            .font(.flightCode(36, weight: .bold))
                            .foregroundStyle(.soraAccent)
                        Text(airport.name)
                            .font(.headline)
                        Text("\(airport.city), \(airport.country)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack {
                        Text("\(visitCount)")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(.soraAccent)
                        Text("visits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Divider()

                // Recent flights
                List(flights.prefix(5)) { flight in
                    FlightRowView(flight: flight)
                        .listRowBackground(Color.soraCard)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(Color.soraNavy.ignoresSafeArea())
            .navigationTitle("Airport")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
