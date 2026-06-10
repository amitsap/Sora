import CoreLocation
import Foundation

/// Computes great circle (geodesic) intermediate points between two coordinates.
/// Used for drawing accurate curved arc routes on MapKit.
func greatCirclePoints(
    from departure: CLLocationCoordinate2D,
    to arrival: CLLocationCoordinate2D,
    steps: Int = 100
) -> [CLLocationCoordinate2D] {
    guard steps > 1 else { return [departure, arrival] }

    // Convert degrees to radians
    let lat1 = departure.latitude * .pi / 180
    let lon1 = departure.longitude * .pi / 180
    let lat2 = arrival.latitude * .pi / 180
    let lon2 = arrival.longitude * .pi / 180

    // Convert to 3D Cartesian unit vectors
    let x1 = cos(lat1) * cos(lon1)
    let y1 = cos(lat1) * sin(lon1)
    let z1 = sin(lat1)

    let x2 = cos(lat2) * cos(lon2)
    let y2 = cos(lat2) * sin(lon2)
    let z2 = sin(lat2)

    // Angular separation (central angle)
    let dotProduct = min(1.0, max(-1.0, x1*x2 + y1*y2 + z1*z2))
    let omega = acos(dotProduct)

    // If points are very close or antipodal, fall back to linear interpolation
    guard omega > 1e-6 else {
        return [departure, arrival]
    }

    var points: [CLLocationCoordinate2D] = []
    points.reserveCapacity(steps + 1)

    for i in 0...steps {
        let t = Double(i) / Double(steps)

        // Spherical linear interpolation (slerp)
        let sinOmega = sin(omega)
        let a = sin((1.0 - t) * omega) / sinOmega
        let b = sin(t * omega) / sinOmega

        let x = a * x1 + b * x2
        let y = a * y1 + b * y2
        let z = a * z1 + b * z2

        // Back to lat/lon
        let lat = atan2(z, sqrt(x*x + y*y)) * 180 / .pi
        let lon = atan2(y, x) * 180 / .pi

        points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    return points
}

/// Returns the angular distance in degrees between two coordinates (for display).
func centralAngleDegrees(
    from departure: CLLocationCoordinate2D,
    to arrival: CLLocationCoordinate2D
) -> Double {
    let lat1 = departure.latitude * .pi / 180
    let lon1 = departure.longitude * .pi / 180
    let lat2 = arrival.latitude * .pi / 180
    let lon2 = arrival.longitude * .pi / 180

    let x1 = cos(lat1) * cos(lon1)
    let y1 = cos(lat1) * sin(lon1)
    let z1 = sin(lat1)

    let x2 = cos(lat2) * cos(lon2)
    let y2 = cos(lat2) * sin(lon2)
    let z2 = sin(lat2)

    let dot = min(1.0, max(-1.0, x1*x2 + y1*y2 + z1*z2))
    return acos(dot) * 180 / .pi
}
