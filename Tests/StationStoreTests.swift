import Foundation

@main
struct StationStoreTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "AllStops/Resources/stations.json"))
        let stations = try JSONDecoder().decode([Station].self, from: data)
        let suite = "AllStopsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StationStore(stations: stations, defaults: defaults)
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            print("PASS: \(message)")
        }
        check(stations.count == 445 && Set(stations.map(\.id)).count == 445, "Complete snapshot with unique complex IDs")
        check(store.collection.count == 424 && store.visitedCount == 0, "Subway-only default, no invented visits")
        check(stations.allSatisfy { $0.latitude > 40 && $0.latitude < 42 && $0.longitude > -75 && $0.longitude < -72 }, "Valid NYC coordinates")
        check(stations.allSatisfy { !$0.routes.isEmpty && Set($0.routes).isSubset(of: Set(StationStore.routeOrder)) }, "All routes supported")
        let unionSquare = stations.first { $0.id == "602" }!
        store.toggle(unionSquare)
        check(store.visitedCount == 1, "One visit per complex")
        check(store.filtered(route: "4", filter: .visited).contains(unionSquare) && store.filtered(route: "L", filter: .visited).contains(unionSquare), "Transfer checkmark shared across lines")
        check(!store.filtered(filter: .remaining).contains(unionSquare), "Visited complex excluded from to-visit filter")
        check(store.filtered(query: "union MANHATTAN", filter: .visited) == [unionSquare], "Search combines case-insensitive station and borough terms")
        let reloaded = StationStore(stations: stations, defaults: defaults)
        check(reloaded.isVisited(unionSquare), "Visit survives store relaunch")
        reloaded.toggle(unionSquare)
        check(StationStore(stations: stations, defaults: defaults).visitedCount == 0, "Unmark persists")
        let sir = stations.first { $0.isStatenIsland }!
        store.includeStatenIsland = true
        store.toggle(sir)
        check(store.collection.count == 445 && store.visitedCount == 2, "SIR opt-in updates collection and totals")
        store.includeStatenIsland = false
        check(store.visitedCount == 1 && store.isVisited(sir), "Hiding SIR preserves its visits")
        store.includeStatenIsland = true
        check(StationStore(stations: stations, defaults: defaults).includeStatenIsland, "Collection preference persists")
        check(store.filtered(query: "not-a-real-station").isEmpty, "Empty search results handled")
        check(InteractionPolicy.canBeginVisitSwipe(x: -100, y: 5, startX: 150), "Left swipe recognized")
        check(!InteractionPolicy.canBeginVisitSwipe(x: 100, y: 5, startX: 150), "Right swipe never changes status")
        check(!InteractionPolicy.canBeginVisitSwipe(x: -100, y: 120, startX: 150), "Vertical movement yields to scrolling")
        check(!InteractionPolicy.canBeginVisitSwipe(x: -100, y: 0, startX: 12), "Screen edge reserved for navigation")
        check(InteractionPolicy.visitSwipeActivated(distance: 64, width: 320), "Swipe activates at twenty percent")
        check(!InteractionPolicy.visitSwipeActivated(distance: 63, width: 320), "Short swipe does not activate")
        check(InteractionPolicy.visitSwipeActivated(distance: 80, width: 400), "Swipe threshold scales with row width")
        check(!InteractionPolicy.visitSwipeActivated(distance: 0, width: 0), "Unlaid-out row never activates")
        check(InteractionPolicy.finishBackSwipe(progress: 0.5, velocity: 0), "Back gesture finishes beyond halfway")
        check(!InteractionPolicy.finishBackSwipe(progress: 0.49, velocity: 0), "Back gesture cancels below halfway")
        check(InteractionPolicy.finishBackSwipe(progress: 0.2, velocity: 700), "Fast edge flick carries momentum")
        check(!InteractionPolicy.finishBackSwipe(progress: 0.05, velocity: 900), "Tiny edge motion does not navigate")
        check(InteractionPolicy.dismissCard(distance: 34, projectedDistance: 34), "Card dismissal distance reduced by 25 percent")
        check(InteractionPolicy.dismissCard(distance: 12, projectedDistance: 120), "Quick downward flick dismisses card")
        check(!InteractionPolicy.dismissCard(distance: 4, projectedDistance: 120), "Tiny movement does not dismiss card")
        check(!InteractionPolicy.dismissCard(distance: -50, projectedDistance: -100), "Upward scroll does not dismiss card")
        check(InteractionPolicy.springVelocity(velocity: 600, remainingDistance: 200) == 3, "Dismissal preserves normalized release velocity")
        check(InteractionPolicy.springVelocity(velocity: 9000, remainingDistance: 1) == 12, "Very fast flick remains bounded")
        store.setVisited(true, for: unionSquare)
        store.setVisited(true, for: unionSquare)
        check(store.isVisited(unionSquare), "Repeated visit action is idempotent")
        let empty = StationStore(stations: [], defaults: defaults)
        check(empty.progress == 0, "Empty dataset avoids division by zero")
    }
}
