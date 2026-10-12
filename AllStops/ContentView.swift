import SwiftUI
import MapKit

enum Style {
    static let accent = Color(red: 0.08, green: 0.36, blue: 0.29)
    static let canvas = Color(uiColor: .systemGroupedBackground)
}

extension Station {
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct ContentView: View {
    @Bindable var store: StationStore
    @State private var showingInfo = false

    var body: some View {
        TabView {
            StationMapView(store: store, onShowInfo: { showingInfo = true })
            .tabItem { Label("Map", systemImage: "map") }
            NavigationStack {
                LinesView(store: store)
                    .toolbar { infoButton }
            }
            .tabItem { Label("By line", systemImage: "list.bullet") }
        }
        .sheet(isPresented: $showingInfo) { InfoView(store: store) }
    }

    @ToolbarContentBuilder private var infoButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("About your collection", systemImage: "info.circle") { showingInfo = true }
        }
    }
}

struct CollectionSummary: View {
    let store: StationStore
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Style.accent.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: store.progress)
                    .stroke(Style.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "tram.fill").font(.title3).foregroundStyle(Style.accent)
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.visitedCount) of \(store.collection.count) visited")
                    .font(.headline).contentTransition(.numericText())
                Text(store.visitedCount == store.collection.count ? "Every stop. A city well explored." : "One stop at a time.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.25), value: store.visitedCount)
    }
}

struct StationMapView: View {
    let store: StationStore
    let onShowInfo: () -> Void
    @State private var query = ""
    @State private var filter: VisitFilter = .all
    @State private var route: String?
    @State private var selected: Station?
    @State private var highlightedID: String?
    @State private var cameraRequest = 0
    @State private var region = Self.cityRegion
    static let cityRegion = MKCoordinateRegion(center: .init(latitude: 40.735, longitude: -73.94), span: .init(latitudeDelta: 0.30, longitudeDelta: 0.27))

    private var visible: [Station] { store.filtered(query: query, route: route, filter: filter) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CollectionSummary(store: store)
                Button("About your collection", systemImage: "info.circle", action: onShowInfo)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .padding(.trailing, 12)
            }
            VStack(spacing: 12) {
                SearchField(text: $query)
                Picker("Visit status", selection: $filter) {
                    ForEach(VisitFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                HStack {
                    Menu {
                        Button("All lines") { route = nil }
                        ForEach(store.routes, id: \.self) { item in
                            Button(item == "SIR" ? "Staten Island Railway" : "\(item) train") { route = item }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let route { RouteBadge(route: route, size: 23) }
                            else { Image(systemName: "line.3.horizontal.decrease") }
                            Text(route == nil ? "All lines" : "Line \(route!)").font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        }
                    }
                    Spacer()
                    Text("\(visible.count) stations").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.bottom, 14)
            ZStack(alignment: .bottomTrailing) {
                StationMap(stations: visible, visitedIDs: store.visitedIDs, selectedID: highlightedID,
                           region: region, cameraRequest: cameraRequest) { station in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        highlightedID = station.id
                        selected = station
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
                if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .background(.regularMaterial)
                        .allowsHitTesting(false)
                }
                Button {
                    fitStations()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Show all matching stations")
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .bottom) {
            // Animate only the card, not the map and its hundreds of annotations.
            Group {
                if let selected {
                    StationCard(station: selected, store: store, onDismissStarted: {
                        if self.selected?.id == selected.id { highlightedID = nil }
                    }) {
                        guard self.selected?.id == selected.id else { return }
                        // The card has already animated fully off-screen.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.selected = nil
                            highlightedID = nil
                        }
                    }
                        .id(selected.id)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                        .transition(.identity)
                }
            }
            .coordinateSpace(name: "stationCardContainer")
        }
        .onAppear { fitStations() }
        .onChange(of: query) { fitStations() }
        .onChange(of: filter) { fitStations() }
        .onChange(of: route) { fitStations() }
        .onChange(of: store.includeStatenIsland) {
            if !store.includeStatenIsland && route == "SIR" { route = nil }
            fitStations()
        }
    }

    private func fitStations() {
        guard !visible.isEmpty else { return }
        let latitudes = visible.map(\.latitude), longitudes = visible.map(\.longitude)
        let minLat = latitudes.min()!, maxLat = latitudes.max()!
        let minLon = longitudes.min()!, maxLon = longitudes.max()!
        region = .init(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2), span: .init(latitudeDelta: max(0.018, (maxLat - minLat) * 1.2), longitudeDelta: max(0.018, (maxLon - minLon) * 1.2)))
        cameraRequest += 1
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search stations or boroughs", text: $text)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityLabel("Search stations or boroughs")
            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly).foregroundStyle(.secondary)
            }
        }
        .padding(11).background(Style.canvas, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct LinesView: View {
    let store: StationStore
    @State private var query = ""
    @State private var filter: VisitFilter = .all
    var body: some View {
        VStack(spacing: 0) {
            CollectionSummary(store: store)
            VStack(spacing: 12) {
                SearchField(text: $query)
                Picker("Visit status", selection: $filter) {
                    ForEach(VisitFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }.padding(.horizontal, 20).padding(.bottom, 12)
            List {
                if !query.isEmpty {
                    let matches = store.filtered(query: query, filter: filter)
                    if matches.isEmpty { ContentUnavailableView.search(text: query) }
                    ForEach(matches) { station in SwipeStationRow(station: station, store: store) }
                } else {
                    Section {
                        ForEach(store.routes, id: \.self) { route in
                            NavigationLink {
                                LineStationsView(route: route, store: store, filter: filter)
                            } label: { LineRow(route: route, store: store, filter: filter) }
                        }
                    } header: { Text("Your city, line by line") }
                    footer: { Text("Transfer stations share one checkmark across every line. Stations within each line are listed A–Z.") }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("By line")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LineRow: View {
    let route: String
    let store: StationStore
    let filter: VisitFilter
    var body: some View {
        let stations = store.filtered(route: route)
        let count = stations.filter(store.isVisited).count
        HStack(spacing: 16) {
            RouteBadge(route: route, size: 40)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(route == "SIR" ? "Staten Island Railway" : "\(route) train").font(.headline)
                    Spacer()
                    Text("\(count) / \(stations.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(count), total: Double(max(1, stations.count))).tint(Style.accent)
                if filter != .all {
                    Text("\(store.filtered(route: route, filter: filter).count) \(filter.rawValue.lowercased())").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(route) line, \(count) of \(stations.count) visited")
    }
}

struct LineStationsView: View {
    let route: String
    let store: StationStore
    @State var filter: VisitFilter
    @State private var query = ""
    var body: some View {
        List {
            Section {
                Picker("Visit status", selection: $filter) {
                    ForEach(VisitFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
            }
            Section("Stations · A–Z") {
                let stations = store.filtered(query: query, route: route, filter: filter)
                if stations.isEmpty {
                    ContentUnavailableView("No matching stations", systemImage: "checklist", description: Text("Try another search or visit filter."))
                }
                ForEach(stations) { station in
                    SwipeStationRow(station: station, store: store)
                }
            }
        }
        .navigationTitle(route == "SIR" ? "Staten Island Railway" : "\(route) train")
        .searchable(text: $query, prompt: "Search this line")
        .background(EdgeBackNavigation().frame(width: 0, height: 0))
    }
}

struct StationRow: View {
    let station: Station
    let store: StationStore
    var body: some View {
        HStack(spacing: 10) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                store.toggle(station)
            } label: {
                Image(systemName: store.isVisited(station) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(store.isVisited(station) ? Style.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(station.name): \(store.isVisited(station) ? "Mark unvisited" : "Mark visited")")
            .accessibilityValue(store.isVisited(station) ? "Visited" : "Not visited")
            VStack(alignment: .leading, spacing: 5) {
                Text(station.name).font(.body.weight(.medium))
                Text(station.borough).font(.caption).foregroundStyle(.secondary)
                RouteBadges(routes: station.routes)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct StationCard: View {
    let station: Station
    let store: StationStore
    let onDismissStarted: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @State private var scrollAtTop = true
    @State private var canDrag: Bool?

    private var height: CGFloat { dynamicTypeSize.isAccessibilitySize ? 400 : 290 }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
            StationDetail(station: station, store: store, onDismiss: { dismiss() }, onScrollPosition: { scrollAtTop = $0 })
        }
        .frame(height: height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 3)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("stationCardContainer"))
                .onChanged { value in
                    guard !isDismissing else { return }
                    if canDrag == nil {
                        // Scrolling long station details must not dismiss the card.
                        canDrag = (scrollAtTop || value.startLocation.y < 24) &&
                            value.translation.height > abs(value.translation.width)
                    }
                    guard canDrag == true else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { dragOffset = max(0, value.translation.height) }
                }
                .onEnded { value in
                    let dragging = canDrag == true
                    canDrag = nil
                    guard dragging, !isDismissing else { return }
                    if InteractionPolicy.dismissCard(distance: value.translation.height, projectedDistance: value.predictedEndTranslation.height) {
                        dismiss(velocity: value.velocity.height)
                    } else {
                        withAnimation(.spring(response: 0.22, dampingFraction: 1)) { dragOffset = 0 }
                    }
                }
        )
        .offset(y: dragOffset)
        .opacity(reduceMotion && isDismissing ? 0 : 1)
        .allowsHitTesting(!isDismissing)
        .accessibilityAction(.escape) { dismiss() }
    }

    private func dismiss(velocity: CGFloat = 0) {
        guard !isDismissing else { return }
        onDismissStarted()
        let destination = max(height + 60, dragOffset + 1)
        let speed = InteractionPolicy.springVelocity(velocity: velocity, remainingDistance: destination - dragOffset)
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.1) :
            .interpolatingSpring(mass: 1, stiffness: 196, damping: 28, initialVelocity: speed)
        // One continuous offset: never reset to zero before removing the card.
        withAnimation(animation, completionCriteria: .removed) {
            isDismissing = true
            if !reduceMotion { dragOffset = destination }
        } completion: {
            onDismiss()
        }
    }
}

private struct CardScrollPosition: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct StationDetail: View {
    let station: Station
    let store: StationStore
    let onDismiss: () -> Void
    let onScrollPosition: (Bool) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(station.borough.uppercased()).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Button("Close", systemImage: "xmark.circle.fill", action: onDismiss).labelStyle(.iconOnly).foregroundStyle(.secondary)
                }
                Text(station.name).font(.title2.bold())
                RouteBadges(routes: station.routes, size: 27)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { store.toggle(station) }
                } label: {
                    Label(store.isVisited(station) ? "Visited · tap to undo" : "Mark as visited", systemImage: store.isVisited(station) ? "checkmark.circle.fill" : "circle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))
                Text("One station complex. One checkmark.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: CardScrollPosition.self, value: geometry.frame(in: .named("cardScroll")).minY)
                })
        }
        .coordinateSpace(name: "cardScroll")
        .onPreferenceChange(CardScrollPosition.self) { onScrollPosition($0 >= -1) }
    }
}

struct RouteBadges: View {
    let routes: [String]
    var size: CGFloat = 20
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { ForEach(routes, id: \.self) { RouteBadge(route: $0, size: size) } }
            Text(routes.joined(separator: " · ")).font(.caption.weight(.bold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lines \(routes.joined(separator: ", "))")
    }
}

struct RouteBadge: View {
    let route: String
    var size: CGFloat = 30
    private var color: Color {
        switch route {
        case "1", "2", "3": Color(red: 0.88, green: 0.16, blue: 0.19)
        case "4", "5", "6": Color(red: 0, green: 0.52, blue: 0.29)
        case "7": Color(red: 0.66, green: 0.20, blue: 0.62)
        case "A", "C", "E": Color(red: 0, green: 0.29, blue: 0.65)
        case "B", "D", "F", "M": Color(red: 0.95, green: 0.40, blue: 0.15)
        case "G": Color(red: 0.43, green: 0.65, blue: 0.24)
        case "J", "Z": Color(red: 0.55, green: 0.36, blue: 0.22)
        case "N", "Q", "R", "W": Color(red: 0.98, green: 0.80, blue: 0.08)
        case "SIR": Color(red: 0.05, green: 0.31, blue: 0.54)
        default: Color(white: 0.48)
        }
    }
    var body: some View {
        Text(route).font(.system(size: size * (route == "SIR" ? 0.30 : 0.55), weight: .bold, design: .rounded))
            .foregroundStyle(["N", "Q", "R", "W"].contains(route) ? .black : .white)
            .frame(width: size, height: size).background(color, in: Circle())
            .accessibilityLabel("\(route) line")
    }
}

struct InfoView: View {
    @Bindable var store: StationStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Your collection") {
                    Toggle("Include Staten Island Railway", isOn: $store.includeStatenIsland)
                    Text("Connected transfer stations count as one visit. Turning off Staten Island Railway hides it without losing its checkmarks.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Simply visited") {
                    Text("Your checkmarks are saved on this iPhone. No account, dates, photos, or location tracking.")
                    Text("The station list works offline. The map background may need an internet connection. Progress does not sync between devices.")
                }
                Section("Station data") {
                    Link("MTA · Stations and Complexes", destination: URL(string: "https://data.ny.gov/Transportation/MTA-Subway-Stations-and-Complexes/5f5g-n3cz")!)
                    Text("Snapshot: October 7, 2026. Lines reflect the MTA’s listed daytime service, not live service changes. All Stops is an independent app, not affiliated with the MTA.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About All Stops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
