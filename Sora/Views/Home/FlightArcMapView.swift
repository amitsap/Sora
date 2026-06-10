import SwiftUI
import MapKit
import CoreLocation

/// Decorative world map showing all flight routes as great-circle arcs.
/// Non-interactive — used as the hero element on HomeView.
struct FlightArcMapView: UIViewRepresentable {
    let flights: [Flight]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.mapType = .standard
        map.overrideUserInterfaceStyle = .dark
        map.delegate = context.coordinator

        // World view
        let worldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 160, longitudeDelta: 340)
        )
        map.setRegion(worldRegion, animated: false)
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        let now = Date()
        let oneYear: TimeInterval = 365 * 24 * 3600

        for flight in flights {
            let points = greatCirclePoints(
                from: flight.departureAirport.coordinate,
                to: flight.arrivalAirport.coordinate,
                steps: 80
            )
            guard points.count > 1 else { continue }

            var coords = points
            let polyline = FlightPolyline(coordinates: &coords, count: coords.count)

            // Recency: 0.0 = one year ago or older, 1.0 = today
            let age = now.timeIntervalSince(flight.departureDate)
            polyline.recency = Float(max(0, min(1, 1.0 - age / oneYear)))

            mapView.addOverlay(polyline)
        }

        // Visited airport dots
        var seenAirports = Set<String>()
        for flight in flights {
            for airport in [flight.departureAirport, flight.arrivalAirport] {
                guard !seenAirports.contains(airport.iataCode) else { continue }
                seenAirports.insert(airport.iataCode)
                let ann = AirportAnnotation(airport: airport)
                mapView.addAnnotation(ann)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? FlightPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            // Recency drives opacity: older = dimmer
            let opacity = CGFloat(max(0.15, Double(polyline.recency)))
            renderer.strokeColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: opacity)
            renderer.lineWidth = 1.5
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is AirportAnnotation else { return nil }
            let id = "airport"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            for subview in view.subviews {
                subview.removeFromSuperview()
            }
            // Small glowing dot
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 5))
            dot.backgroundColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.8)
            dot.layer.cornerRadius = 2.5
            view.addSubview(dot)
            view.frame = dot.frame
            view.canShowCallout = false
            return view
        }
    }
}

/// MKPolyline subclass that carries a recency value (0.0–1.0).
final class FlightPolyline: MKPolyline {
    var recency: Float = 1.0
}

/// Airport annotation for the map.
final class AirportAnnotation: NSObject, MKAnnotation {
    let airport: Airport
    var coordinate: CLLocationCoordinate2D { airport.coordinate }
    var title: String? { airport.iataCode }
    var subtitle: String? { airport.city }

    init(airport: Airport) { self.airport = airport }
}
