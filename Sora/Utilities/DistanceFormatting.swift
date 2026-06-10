import Foundation

enum DistanceUnit: String, CaseIterable {
    case miles
    case kilometers

    static var current: DistanceUnit {
        DistanceUnit(
            rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? DistanceUnit.miles.rawValue
        ) ?? .miles
    }

    var displayName: String {
        switch self {
        case .miles: return "Miles"
        case .kilometers: return "Kilometers"
        }
    }

    var abbreviation: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }

    func value(fromMiles miles: Double) -> Double {
        switch self {
        case .miles:
            return miles
        case .kilometers:
            return miles * 1.60934
        }
    }

    func format(fromMiles miles: Double, maximumFractionDigits: Int = 0, includeUnit: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits

        let value = value(fromMiles: miles)
        let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "0"
        return includeUnit ? "\(formattedValue) \(abbreviation)" : formattedValue
    }
}
