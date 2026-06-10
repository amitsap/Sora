import SwiftUI

enum CabinClass: String, CaseIterable, Codable {
    case economy = "economy"
    case premiumEconomy = "premiumEconomy"
    case business = "business"
    case first = "first"

    var displayName: String {
        switch self {
        case .economy:        return "Economy"
        case .premiumEconomy: return "Premium Economy"
        case .business:       return "Business"
        case .first:          return "First"
        }
    }

    // IATA single-letter codes
    var shortCode: String {
        switch self {
        case .economy:        return "Y"
        case .premiumEconomy: return "W"
        case .business:       return "J"
        case .first:          return "F"
        }
    }

    var badgeColor: Color {
        switch self {
        case .economy:        return Color(.systemGray)
        case .premiumEconomy: return Color(red: 0.3, green: 0.75, blue: 0.4)
        case .business:       return Color(red: 1.0, green: 0.75, blue: 0.0)
        case .first:          return Color(red: 0.9, green: 0.55, blue: 0.15)
        }
    }
}
