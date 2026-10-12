import Foundation

/// Shared gesture decisions, separate from rendering so they can be tested.
enum InteractionPolicy {
    static let backEdgeWidth: CGFloat = 24
    static let cardDismissDistance: CGFloat = 45 * 0.75

    static func canBeginVisitSwipe(x: CGFloat, y: CGFloat, startX: CGFloat) -> Bool {
        startX > backEdgeWidth && x < 0 && -x > abs(y) * 1.5
    }

    static func visitSwipeActivated(distance: CGFloat, width: CGFloat) -> Bool {
        width > 0 && distance >= width * 0.2
    }

    static func finishBackSwipe(progress: CGFloat, velocity: CGFloat) -> Bool {
        progress >= 0.5 || (progress >= 0.15 && velocity > 650)
    }

    static func dismissCard(distance: CGFloat, projectedDistance: CGFloat) -> Bool {
        distance >= cardDismissDistance || (distance > 8 && projectedDistance > 75)
    }

    static func springVelocity(velocity: CGFloat, remainingDistance: CGFloat) -> Double {
        // Normalize points/second to animation-distance/second; cap below critical
        // spring frequency to avoid overshooting and returning into view.
        Double(min(12, max(0, velocity / max(1, remainingDistance))))
    }
}
