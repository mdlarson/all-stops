import SwiftUI
import UIKit

/// Drive a real navigation pop continuously from a pan starting at the left edge.
struct EdgeBackNavigation: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.apply() }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var contentGesture: UIGestureRecognizer?
        private var contentWasEnabled: Bool?
        private weak var edgeGesture: UIGestureRecognizer?
        private var edgeWasEnabled: Bool?
        private weak var gestureView: UIView?
        private var initialPoint = CGPoint.zero
        private var transition: PopTransition?
        private lazy var backPan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            return pan
        }()

        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if transition == nil { restore() }
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { apply() } else if transition == nil { restore() }
        }
        func apply() {
            guard transition == nil, let navigation = navigationController else { return }
            if gestureView !== navigation.view {
                restore()
                gestureView = navigation.view
                navigation.view.addGestureRecognizer(backPan)
                edgeGesture = navigation.interactivePopGestureRecognizer
                edgeWasEnabled = edgeGesture?.isEnabled
                if #available(iOS 26.0, *) {
                    contentGesture = navigation.interactiveContentPopGestureRecognizer
                    contentWasEnabled = contentGesture?.isEnabled
                }
            }
            edgeGesture?.isEnabled = false
            contentGesture?.isEnabled = false
        }
        func restore() {
            guard transition == nil else { return }
            gestureView?.removeGestureRecognizer(backPan)
            if let contentWasEnabled { contentGesture?.isEnabled = contentWasEnabled }
            if let edgeWasEnabled { edgeGesture?.isEnabled = edgeWasEnabled }
            gestureView = nil; contentGesture = nil; edgeGesture = nil
            contentWasEnabled = nil; edgeWasEnabled = nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            initialPoint = touch.location(in: gestureView)
            return transition == nil && initialPoint.x >= 0 && initialPoint.x <= InteractionPolicy.backEdgeWidth
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation = navigationController, navigation.viewControllers.count > 1,
                  navigation.transitionCoordinator == nil else { return false }
            let point = backPan.location(in: gestureView)
            return point.x - initialPoint.x > abs(point.y - initialPoint.y) * 1.5
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            let width = max(1, gestureView?.bounds.width ?? 1)
            let progress = min(1, max(0, (recognizer.location(in: gestureView).x - initialPoint.x) / width))
            switch recognizer.state {
            case .began:
                guard let navigation = navigationController else { return }
                let transition = PopTransition(navigation: navigation)
                self.transition = transition
                // Retain this controller until UIKit completes or cancels the pop.
                transition.onCompletion = { [self] completed in
                    self.transition = nil
                    if completed { restore() } else { apply() }
                }
                navigation.delegate = transition
                if navigation.popViewController(animated: true) == nil {
                    transition.complete(completed: false)
                    return
                }
                transition.driver.update(progress)
            case .changed:
                transition?.driver.update(progress)
            case .ended:
                guard let transition else { return }
                transition.driver.update(progress)
                transition.driver.completionCurve = .easeOut
                transition.driver.completionSpeed = min(2, max(0.8, abs(recognizer.velocity(in: gestureView).x) / width))
                if InteractionPolicy.finishBackSwipe(progress: progress, velocity: recognizer.velocity(in: gestureView).x) {
                    transition.driver.finish()
                } else { transition.driver.cancel() }
            case .cancelled, .failed:
                transition?.driver.cancel()
            default: break
            }
        }
    }

    final class PopTransition: NSObject, UINavigationControllerDelegate {
        let driver = UIPercentDrivenInteractiveTransition()
        private weak var navigation: UINavigationController?
        private let previousDelegate: UINavigationControllerDelegate?
        var onCompletion: ((Bool) -> Void)?
        private var completed = false
        private weak var originalTop: UIViewController?

        init(navigation: UINavigationController) {
            self.navigation = navigation
            previousDelegate = navigation.delegate
            originalTop = navigation.topViewController
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (previousDelegate?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? { previousDelegate }
        func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            if operation == .pop { return SlidePop() }
            return previousDelegate?.navigationController?(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
        }
        func navigationController(_ navigationController: UINavigationController, interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? { driver }
        func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
            previousDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
        }
        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            previousDelegate?.navigationController?(navigationController, didShow: viewController, animated: animated)
            complete(completed: viewController !== originalTop)
        }
        func complete(completed: Bool) {
            guard !self.completed else { return }
            self.completed = true
            if navigation?.delegate === self { navigation?.delegate = previousDelegate }
            let callback = onCompletion
            onCompletion = nil
            callback?(completed)
        }
    }

    final class SlidePop: NSObject, UIViewControllerAnimatedTransitioning {
        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.3 }
        func animateTransition(using context: UIViewControllerContextTransitioning) {
            guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
                  let toController = context.viewController(forKey: .to) else { context.completeTransition(false); return }
            let container = context.containerView
            let width = container.bounds.width
            to.frame = context.finalFrame(for: toController)
            container.insertSubview(to, belowSubview: from)
            to.transform = UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(translationX: -width * 0.25, y: 0)
            UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: .curveLinear) {
                from.transform = CGAffineTransform(translationX: width, y: 0)
                to.transform = .identity
            } completion: { _ in
                let finished = !context.transitionWasCancelled
                from.transform = .identity
                to.transform = .identity
                context.completeTransition(finished)
            }
        }
    }
}
