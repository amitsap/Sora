import SwiftUI
import SwiftData

@main
struct SoraApp: App {
    let container: ModelContainer
    let aeroDataBox = AeroDataBoxService()
    let openSky = OpenSkyService()

    init() {
        // Ensure Application Support directory exists before SwiftData tries to write there
        let appSupport = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let schema = Schema([Flight.self, AircraftType.self])
        // Don't pass schema to ModelConfiguration — let ModelContainer own it (matches Karui pattern)
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .environment(aeroDataBox)
        .environment(openSky)
    }
}
