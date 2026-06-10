import SwiftUI

struct ContentView: View {
    @State private var selectedTab: RootTab = .home
    @State private var addFlightDraft: FlightDraft?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView { draft in
                addFlightDraft = draft
            }
            .tabItem {
                Label("Home", systemImage: "airplane")
            }
            .tag(RootTab.home)

            LogbookView()
                .tabItem {
                    Label("Logbook", systemImage: "list.bullet.clipboard")
                }
                .tag(RootTab.logbook)

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
                .tag(RootTab.stats)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(RootTab.settings)
        }
        .tint(.soraAccent)
        .sheet(item: $addFlightDraft) { draft in
            AddFlightView(prefill: draft)
        }
        .onOpenURL { url in
            guard let draft = FlightDraft(url: url) else { return }
            selectedTab = .home
            addFlightDraft = draft
        }
    }
}

private enum RootTab: Hashable {
    case home
    case logbook
    case stats
    case settings
}

// MARK: - Design System

extension Color {
    static let soraAccent = Color(red: 0.2, green: 0.6, blue: 1.0)
    static let soraAmber  = Color(red: 1.0, green: 0.75, blue: 0.0)
    static let soraNavy   = Color(red: 0.05, green: 0.08, blue: 0.15)
    static let soraCard   = Color(red: 0.08, green: 0.12, blue: 0.20)
}

// Enables .soraAccent in SwiftUI modifiers like .foregroundStyle(.soraAccent)
extension ShapeStyle where Self == Color {
    static var soraAccent: Color { .init(red: 0.2, green: 0.6, blue: 1.0) }
    static var soraAmber:  Color { .init(red: 1.0, green: 0.75, blue: 0.0) }
    static var soraNavy:   Color { .init(red: 0.05, green: 0.08, blue: 0.15) }
    static var soraCard:   Color { .init(red: 0.08, green: 0.12, blue: 0.20) }
}

extension Font {
    // Monospaced font for IATA codes and flight numbers
    static func flightCode(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
