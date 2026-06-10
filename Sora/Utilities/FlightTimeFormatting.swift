import Foundation

enum FlightTimeFormatting {
    static func countdownString(until date: Date, relativeTo now: Date = Date()) -> String {
        let interval = max(0, date.timeIntervalSince(now))
        let totalMinutes = Int(interval.rounded(.down)) / 60

        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 {
                return "\(days)d \(hours)h"
            }
            return "\(days)d"
        }

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }

        return "\(max(minutes, 1))m"
    }
}
