import SwiftUI
import UIKit

struct SwipeStationRow: View {
    let station: Station
    let store: StationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwipeRowHost(visited: store.isVisited(station), reduceMotion: reduceMotion,
                     setVisited: { store.setVisited($0, for: station) },
                     content: StationRow(station: station, store: store)
                        .accessibilityAction(named: "Toggle visited status") {
                            store.toggle(station)
                        })
    }
}

/// UIKit decides the direction before claiming a pan. Vertical movement fails
/// this recognizer immediately, so List's scroll recognizer can take over.
private struct SwipeRowHost<Content: View>: UIViewControllerRepresentable {
    let visited: Bool
    let reduceMotion: Bool
    let setVisited: (Bool) -> Void
    let content: Content

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: content)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.host.rootView = content
        controller.visited = visited
        controller.reduceMotion = reduceMotion
        controller.setVisited = setVisited
        controller.refreshLabel()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: Controller, context: Context) -> CGSize? {
        uiViewController.host.sizeThatFits(in: CGSize(width: proposal.width ?? 320, height: .greatestFiniteMagnitude))
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        let host: UIHostingController<Content>
        var visited = false
        var reduceMotion = false
        var setVisited: (Bool) -> Void = { _ in }
        private let actionLabel = UILabel()
        private var targetVisited = false
        private var committed = false
        private var active = false
        private var initialTouchX: CGFloat = 0
        private var pan: UIPanGestureRecognizer!

        init(content: Content) {
            host = UIHostingController(rootView: content)
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.clipsToBounds = true
            actionLabel.font = .preferredFont(forTextStyle: .caption1)
            actionLabel.adjustsFontForContentSizeCategory = true
            actionLabel.textColor = .white
            actionLabel.textAlignment = .right
            actionLabel.isAccessibilityElement = false
            actionLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(actionLabel)
            NSLayoutConstraint.activate([
                actionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
                actionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                actionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8)
            ])
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            host.view.backgroundColor = .secondarySystemGroupedBackground
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            host.didMove(toParent: self)
            pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)
            refreshLabel()
        }

        func refreshLabel() {
            guard isViewLoaded else { return }
            let action = active ? targetVisited : !visited
            actionLabel.text = action ? "✓ Visited" : "↶ Unvisited"
            view.backgroundColor = action ? UIColor(Style.accent) : .systemOrange
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let movement = pan.translation(in: view)
            let location = pan.location(in: view.window)
            let translation = pan.translation(in: view.window)
            initialTouchX = location.x - translation.x
            return InteractionPolicy.canBeginVisitSwipe(x: movement.x, y: movement.y,
                                                       startX: initialTouchX)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // List and SwiftUI install their own recognizers on ancestor views.
            // Don't let those cancel an already direction-checked row pan.
            true
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                active = true
                committed = false
                targetVisited = !visited
                refreshLabel()
                fallthrough
            case .changed:
                // The pan's translation resets when recognition begins. Measure
                // from the original touch so the activation distance includes it.
                let distance = max(0, initialTouchX - recognizer.location(in: view.window).x)
                host.view.transform = CGAffineTransform(translationX: -min(distance, view.bounds.width), y: 0)
                if !committed && InteractionPolicy.visitSwipeActivated(distance: distance, width: view.bounds.width) {
                    committed = true // Exactly once, even if the finger moves back and forth.
                    UISelectionFeedbackGenerator().selectionChanged()
                    setVisited(targetVisited)
                }
            case .ended, .cancelled, .failed:
                active = false
                UIView.animate(withDuration: reduceMotion ? 0 : 0.16, delay: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.host.view.transform = .identity
                } completion: { _ in self.refreshLabel() }
            default: break
            }
        }
    }
}
