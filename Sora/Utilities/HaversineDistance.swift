import CoreLocation
import Foundation

/// Haversine formula — computes great circle distance between two coordinates.
/// Returns distance in miles.
func haversineDistance(
    from: CLLocationCoordinate2D,
    to: CLLocationCoordinate2D
) -> Double {
    let earthRadiusMiles = 3958.8

    let lat1 = from.latitude * .pi / 180
    let lat2 = to.latitude * .pi / 180
    let dLat = (to.latitude - from.latitude) * .pi / 180
    let dLon = (to.longitude - from.longitude) * .pi / 180

    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))

    return earthRadiusMiles * c
}

/// Returns distance in kilometers.
func haversineDistanceKm(
    from: CLLocationCoordinate2D,
    to: CLLocationCoordinate2D
) -> Double {
    haversineDistance(from: from, to: to) * 1.60934
}
