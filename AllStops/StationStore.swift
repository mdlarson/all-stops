import Foundation
import Observation

struct Station: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let borough: String
    let routes: [String]
    let latitude: Double
    let longitude: Double

    var isStatenIsland: Bool { routes.contains("SIR") }

    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let text = "\(name) \(borough) \(routes.joined(separator: " "))"
        return terms.allSatisfy { text.localizedStandardContains(String($0)) }
    }
}

enum VisitFilter: String, CaseIterable, Identifiable {
    case all = "All", remaining = "To visit", visited = "Visited"
    var id: String { rawValue }
}

@Observable
final class StationStore {
    static let routeOrder = ["1", "2", "3", "4", "5", "6", "7", "A", "C", "E", "B", "D", "F", "M", "G", "J", "Z", "L", "N", "Q", "R", "W", "S", "SIR"]
    let stations: [Station]
    private(set) var visitedIDs: Set<String>
    var includeStatenIsland: Bool {
        didSet { defaults.set(includeStatenIsland, forKey: "includeStatenIsland") }
    }
    private let defaults: UserDefaults

    init(stations: [Station], defaults: UserDefaults = .standard) {
        self.stations = stations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.defaults = defaults
        visitedIDs = Set(defaults.stringArray(forKey: "visitedComplexIDs") ?? [])
        includeStatenIsland = defaults.bool(forKey: "includeStatenIsland")
    }

    static func load() throws -> StationStore {
        guard let url = Bundle.main.url(forResource: "stations", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let stations = try JSONDecoder().decode([Station].self, from: Data(contentsOf: url))
        return StationStore(stations: stations)
    }

    var collection: [Station] { stations.filter { includeStatenIsland || !$0.isStatenIsland } }
    var visitedCount: Int { collection.filter(isVisited).count }
    var progress: Double { collection.isEmpty ? 0 : Double(visitedCount) / Double(collection.count) }
    var routes: [String] { Self.routeOrder.filter { route in collection.contains { $0.routes.contains(route) } } }

    func isVisited(_ station: Station) -> Bool { visitedIDs.contains(station.id) }

    func toggle(_ station: Station) {
        setVisited(!isVisited(station), for: station)
    }

    func setVisited(_ visited: Bool, for station: Station) {
        if visited { visitedIDs.insert(station.id) }
        else { visitedIDs.remove(station.id) }
        defaults.set(visitedIDs.sorted(), forKey: "visitedComplexIDs")
    }

    func filtered(query: String = "", route: String? = nil, filter: VisitFilter = .all) -> [Station] {
        collection.filter { station in
            station.matches(query) && (route == nil || station.routes.contains(route!)) &&
            (filter == .all || (filter == .visited ? isVisited(station) : !isVisited(station)))
        }
    }
}
