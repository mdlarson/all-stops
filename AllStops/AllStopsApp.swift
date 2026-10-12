import SwiftUI

@main
struct AllStopsApp: App {
    @State private var store: StationStore?
    @State private var loadFailed = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let store { ContentView(store: store) }
                else if loadFailed {
                    ContentUnavailableView("Stations couldn’t be loaded", systemImage: "tram.fill", description: Text("The bundled station list is missing or unreadable. Please reinstall the app."))
                } else { ProgressView("Loading stations…") }
            }
            .tint(Style.accent)
            .task {
                guard store == nil else { return }
                do { store = try StationStore.load() }
                catch { loadFailed = true }
            }
        }
    }
}
