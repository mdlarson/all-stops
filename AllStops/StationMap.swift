import SwiftUI
import MapKit

/// Keep annotation views alive; update only the pins whose appearance changed.
struct StationMap: UIViewRepresentable {
    let stations: [Station]
    let visitedIDs: Set<String>
    let selectedID: String?
    let region: MKCoordinateRegion
    let cameraRequest: Int
    let onSelect: (Station) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.delegate = context.coordinator
        map.register(Pin.self, forAnnotationViewWithReuseIdentifier: "station")
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.visitedIDs = visitedIDs
        coordinator.selectedID = selectedID
        let wanted = Set(stations.map(\.id))
        let removed = coordinator.annotations.keys.filter { !wanted.contains($0) }
        map.removeAnnotations(removed.compactMap { coordinator.annotations.removeValue(forKey: $0) })
        let added = stations.filter { coordinator.annotations[$0.id] == nil }.map { Annotation(station: $0) }
        added.forEach { coordinator.annotations[$0.station.id] = $0 }
        if !added.isEmpty { map.addAnnotations(added) }
        for annotation in coordinator.annotations.values {
            if let pin = map.view(for: annotation) as? Pin {
                pin.configure(visited: visitedIDs.contains(annotation.station.id), selected: selectedID == annotation.station.id)
            }
        }
        if coordinator.cameraRequest != cameraRequest {
            let animated = coordinator.cameraRequest != nil && !UIAccessibility.isReduceMotionEnabled
            coordinator.cameraRequest = cameraRequest
            map.setRegion(region, animated: animated)
        }
    }

    final class Annotation: NSObject, MKAnnotation {
        let station: Station
        var coordinate: CLLocationCoordinate2D { station.coordinate }
        init(station: Station) { self.station = station }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var annotations: [String: Annotation] = [:]
        var visitedIDs: Set<String> = []
        var selectedID: String?
        var cameraRequest: Int?
        var onSelect: (Station) -> Void = { _ in }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? Annotation else { return nil }
            let pin = mapView.dequeueReusableAnnotationView(withIdentifier: "station", for: annotation) as! Pin
            pin.configure(visited: visitedIDs.contains(annotation.station.id), selected: selectedID == annotation.station.id)
            pin.onActivate = { [weak self] in self?.onSelect(annotation.station) }
            return pin
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc func tapped(_ tap: UITapGestureRecognizer) {
            guard let map = tap.view as? MKMapView, tap.state == .ended else { return }
            let location = tap.location(in: map)
            // A single-finger tap selects immediately, without waiting for MapKit's
            // selection animation. Pinch and pan remain entirely with MapKit.
            let candidates = map.annotations.compactMap { annotation -> (Annotation, CGFloat)? in
                guard let annotation = annotation as? Annotation,
                      let pin = map.view(for: annotation), !pin.isHidden else { return nil }
                let point = pin.convert(location, from: map)
                guard pin.bounds.contains(point) else { return nil }
                return (annotation, hypot(point.x - pin.bounds.midX, point.y - pin.bounds.midY))
            }
            if let closest = candidates.min(by: { $0.1 < $1.1 }) { onSelect(closest.0.station) }
        }
    }

    final class Pin: MKAnnotationView {
        private let dot = UIView()
        private let check = UILabel()
        private var appearance: (Bool, Bool)?
        var onActivate: () -> Void = {}

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            frame = CGRect(x: 0, y: 0, width: 44, height: 44)
            isEnabled = false // Selection is handled by the map's nonblocking tap recognizer.
            isAccessibilityElement = true
            accessibilityTraits = .button
            displayPriority = .required
            collisionMode = .circle
            dot.isUserInteractionEnabled = false
            check.isUserInteractionEnabled = false
            check.font = .systemFont(ofSize: 10, weight: .heavy)
            check.textAlignment = .center
            check.text = "✓"
            check.textColor = .white
            addSubview(dot)
            dot.addSubview(check)
            registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (pin: Pin, _: UITraitCollection) in
                if let current = pin.appearance {
                    pin.appearance = nil
                    pin.configure(visited: current.0, selected: current.1)
                }
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func accessibilityActivate() -> Bool { onActivate(); return true }
        func configure(visited: Bool, selected: Bool) {
            if let station = (annotation as? Annotation)?.station {
                accessibilityLabel = "\(station.name), \(station.borough)"
                accessibilityValue = visited ? "Visited" : "Not visited"
            }
            guard appearance?.0 != visited || appearance?.1 != selected else { return }
            appearance = (visited, selected)
            UIView.performWithoutAnimation {
                let size: CGFloat = selected ? 30 : 20
                self.dot.frame = CGRect(x: (44 - size) / 2, y: (44 - size) / 2, width: size, height: size)
                self.dot.layer.cornerRadius = size / 2
                self.dot.layer.borderWidth = 2
                self.dot.layer.borderColor = (visited ? UIColor.white : UIColor.label).cgColor
                self.dot.backgroundColor = visited ? UIColor(Style.accent) : .systemBackground
                self.check.frame = self.dot.bounds
                self.check.text = visited ? "✓" : "•"
                self.check.textColor = visited ? .white : .label
            }
        }
    }
}
