import UIKit

private var easyNativeNavigationObserverKey: UInt8 = 0

public enum NativeFlowState {
    case idle
    case active
    case closing
}

public final class EasyNativeNavigationController: UINavigationController {
    public var isPresentedFlow = false

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            EasyNativeFlowManager.shared.clearIfActive(self)
        }
    }
}

private final class EasyNativeNavigationObserver: NSObject, UINavigationControllerDelegate {
    weak var forwardedDelegate: UINavigationControllerDelegate?
    private var knownViewControllers: [UIViewController] = []

    func startObserving(_ navigationController: UINavigationController) {
        if forwardedDelegate == nil,
           let delegate = navigationController.delegate,
           delegate !== self {
            forwardedDelegate = delegate
        }
        knownViewControllers = navigationController.viewControllers
        navigationController.delegate = self
    }

    func updateStack(_ viewControllers: [UIViewController]) {
        knownViewControllers = viewControllers
    }

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        forwardedDelegate?.navigationController?(
            navigationController,
            willShow: viewController,
            animated: animated
        )
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        let current = navigationController.viewControllers
        let popped = knownViewControllers.filter { old in
            !current.contains(where: { $0 === old })
        }

        popped.reversed().forEach {
            EasyNativeFlowManager.shared.completeRouteIfNeeded(
                $0,
                result: nil,
                action: "nativePop"
            )
        }
        EasyNativeFlowManager.shared.handleNavigationStackChanged(
            navigationController
        )
        knownViewControllers = current

        forwardedDelegate?.navigationController?(
            navigationController,
            didShow: viewController,
            animated: animated
        )
    }
}

private extension UINavigationController {
    var easyNativeNavigationObserver: EasyNativeNavigationObserver? {
        get {
            return objc_getAssociatedObject(
                self,
                &easyNativeNavigationObserverKey
            ) as? EasyNativeNavigationObserver
        }
        set {
            objc_setAssociatedObject(
                self,
                &easyNativeNavigationObserverKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

/// Coordinates a native flow. It is not a stack manager; UIKit owns the real stack.
public final class EasyNativeFlowManager {
    public static let shared = EasyNativeFlowManager()

    private weak var flowRootNavigationController: UINavigationController?
    private weak var flowRootViewController: UIViewController?
    private weak var activeNavigationController: UINavigationController?
    private var completedRequestIds: Set<String> = []
    private var state: NativeFlowState = .idle

    private init() {}

    private func validateState() {
        guard state != .idle, let root = flowRootNavigationController else { return }
        if root is EasyNativeNavigationController { return }
        
        if let flowRoot = flowRootViewController {
            if !root.viewControllers.contains(flowRoot) {
                clearState()
            }
        } else {
            clearState()
        }
    }

    private func clearState() {
        flowRootNavigationController = nil
        flowRootViewController = nil
        activeNavigationController = nil
        state = .idle
    }

    public var hasActiveNativeFlow: Bool {
        validateState()
        return state != .idle || flowRootNavigationController != nil
    }

    public func push(
        routeName: String,
        arguments: Any?,
        from rootNav: UINavigationController?,
        requestId: String?
    ) -> [String: Any] {
        validateState()
        if let error = checkCanRoute(action: "nativePush") {
            return error
        }
        guard let viewController = EasyNativeRouteRegistry.shared.makeViewController(
            routeName: routeName,
            arguments: arguments
        ) else {
            return failure("Native route is not registered: \(routeName)", action: "nativePush")
        }
        attachRequestId(requestId, to: viewController)

        if let active = currentNavigationController() {
            EasyNativeLogger.log(.debug, "native push \(routeName)")
            observeNavigationController(active)
            active.pushViewController(viewController, animated: true)
            return success(action: "nativePush")
        }

        guard let rootNav = rootNav else {
            return failure("Root UINavigationController is missing", action: "nativePush")
        }

        flowRootNavigationController = rootNav
        flowRootViewController = viewController
        activeNavigationController = rootNav
        state = .active
        EasyNativeLogger.log(.debug, "open native flow \(routeName)")
        observeNavigationController(rootNav)
        rootNav.pushViewController(viewController, animated: true)
        return success(action: "openNativeFlow")
    }

    public func present(
        routeName: String,
        arguments: Any?,
        from rootNav: UINavigationController?,
        requestId: String?
    ) -> [String: Any] {
        validateState()
        if let error = checkCanRoute(action: "nativePresent") {
            return error
        }
        guard let viewController = EasyNativeRouteRegistry.shared.makeViewController(
            routeName: routeName,
            arguments: arguments
        ) else {
            return failure("Native route is not registered: \(routeName)", action: "nativePresent")
        }
        attachRequestId(requestId, to: viewController)

        let container = EasyNativeNavigationController(rootViewController: viewController)
        container.isNavigationBarHidden = true
        container.isPresentedFlow = true
        container.modalPresentationStyle = .fullScreen
        observeNavigationController(container)

        let presenter = (currentNavigationController() ?? rootNav)?.easyNativeTopMost()
        guard let presenter = presenter else {
            return failure("Presenter is missing", action: "nativePresent")
        }

        if flowRootNavigationController == nil {
            flowRootNavigationController = container
            flowRootViewController = viewController
        }
        activeNavigationController = container
        state = .active
        EasyNativeLogger.log(.debug, "native present \(routeName)")
        presenter.present(container, animated: true)
        return success(action: "nativePresent")
    }

    public func replace(routeName: String, arguments: Any?, result: Any?, requestId: String?) -> [String: Any] {
        validateState()
        if let error = checkCanRoute(action: "nativeReplace") {
            return error
        }
        guard let viewController = EasyNativeRouteRegistry.shared.makeViewController(
            routeName: routeName,
            arguments: arguments
        ) else {
            return failure("Native route is not registered: \(routeName)", action: "nativeReplace")
        }
        attachRequestId(requestId, to: viewController)

        guard let active = currentNavigationController() else {
            return failure("No active native flow", action: "nativeReplace")
        }

        var stack = active.viewControllers
        let oldLast = stack.last
        if stack.isEmpty {
            stack = [viewController]
        } else {
            stack[stack.count - 1] = viewController
        }
        
        if active === flowRootNavigationController, oldLast === flowRootViewController {
            flowRootViewController = viewController
        }
        if let oldLast = oldLast {
            completeRouteIfNeeded(oldLast, result: result, action: "nativeReplace")
        }
        
        observeNavigationController(active)
        active.setViewControllers(stack, animated: true)
        EasyNativeLogger.log(.debug, "native replace \(routeName)")
        return success(action: "nativeReplace")
    }

    public func pop(result: Any?) -> [String: Any] {
        validateState()
        if let error = checkCanRoute(action: "nativePop") {
            return error
        }
        guard let active = currentNavigationController() else {
            return failure("No active native flow", action: "nativePop")
        }

        let isPoppingFlowRoot = (active === flowRootNavigationController && active.viewControllers.last === flowRootViewController)

        if active.viewControllers.count <= 1 || isPoppingFlowRoot {
            if active !== flowRootNavigationController || active is EasyNativeNavigationController {
                active.viewControllers.reversed().enumerated().forEach { index, viewController in
                    completeRouteIfNeeded(
                        viewController,
                        result: index == 0 ? result : nil,
                        action: "nativeDismiss"
                    )
                }
                active.dismiss(animated: true) {
                    self.activeNavigationController = self.currentNavigationController()
                }
                EasyNativeLogger.log(.debug, "native dismiss presented flow")
                return success(action: "nativeDismiss")
            }
            return closeAll(result: result)
        }

        if let top = active.viewControllers.last {
            completeRouteIfNeeded(top, result: result, action: "nativePop")
        }
        observeNavigationController(active)
        active.popViewController(animated: true)
        EasyNativeLogger.log(.debug, "native pop")
        return success(action: "nativePop")
    }

    public func popUntil(routeName: String) -> [String: Any] {
        validateState()
        if let error = checkCanRoute(action: "nativePopUntil") {
            return error
        }
        guard let active = currentNavigationController() else {
            return failure("No active native flow", action: "nativePopUntil")
        }
        guard let target = active.viewControllers.last(where: { $0.easyNativeRouteName == routeName }) else {
            return failure("Route not found in native stack: \(routeName)", action: "nativePopUntil")
        }
        if let index = active.viewControllers.firstIndex(of: target) {
            active.viewControllers.suffix(from: index + 1).forEach {
                completeRouteIfNeeded($0, result: nil, action: "nativePopUntil")
            }
        }
        observeNavigationController(active)
        active.popToViewController(target, animated: true)
        EasyNativeLogger.log(.debug, "native popUntil \(routeName)")
        return success(action: "nativePopUntil")
    }

    public func pushAndRemoveUntil(
        routeName: String,
        arguments: Any?,
        untilRoute: String?,
        requestId: String?
    ) -> [String: Any] {
        validateState()
        if let error = checkCanRoute(action: "nativePushAndRemoveUntil") {
            return error
        }
        guard let viewController = EasyNativeRouteRegistry.shared.makeViewController(
            routeName: routeName,
            arguments: arguments
        ) else {
            return failure("Native route is not registered: \(routeName)", action: "nativePushAndRemoveUntil")
        }
        attachRequestId(requestId, to: viewController)
        guard let active = currentNavigationController() else {
            return failure("No active native flow", action: "nativePushAndRemoveUntil")
        }

        var stack = active.viewControllers
        var removedFlowRoot = false

        if let untilRoute = untilRoute,
           let index = stack.lastIndex(where: { $0.easyNativeRouteName == untilRoute }) {
            let toRemove = stack.suffix(from: index + 1)
            toRemove.forEach {
                completeRouteIfNeeded($0, result: nil, action: "nativePushAndRemoveUntil")
            }
            if toRemove.contains(where: { $0 === flowRootViewController }) {
                removedFlowRoot = true
            }
            stack = Array(stack.prefix(index + 1))
        } else {
            if active === flowRootNavigationController, let flowRoot = flowRootViewController, let index = stack.firstIndex(of: flowRoot) {
                stack.suffix(from: index).forEach {
                    completeRouteIfNeeded($0, result: nil, action: "nativePushAndRemoveUntil")
                }
                stack = Array(stack.prefix(index))
                removedFlowRoot = true
            } else {
                stack.forEach {
                    completeRouteIfNeeded($0, result: nil, action: "nativePushAndRemoveUntil")
                }
                if stack.contains(where: { $0 === flowRootViewController }) {
                    removedFlowRoot = true
                }
                stack.removeAll()
            }
        }
        
        stack.append(viewController)
        
        if active === flowRootNavigationController && removedFlowRoot {
            flowRootViewController = viewController
        }
        
        observeNavigationController(active)
        active.setViewControllers(stack, animated: true)
        EasyNativeLogger.log(.debug, "native pushAndRemoveUntil \(routeName)")
        return success(action: "nativePushAndRemoveUntil")
    }

    public func closeAll(result: Any?) -> [String: Any] {
        validateState()
        guard Thread.isMainThread else {
            return failure("Must be called from main thread", action: "closeNativeFlow")
        }
        guard let root = flowRootNavigationController else {
            state = .idle
            return success(action: "noActiveNativeFlow")
        }
        if state == .closing {
            return success(action: "nativeFlowAlreadyClosing")
        }
        state = .closing
        completeActiveRoutes(result: result, action: "closeNativeFlow")

        let completion = {
            self.flowRootNavigationController = nil
            self.flowRootViewController = nil
            self.activeNavigationController = nil
            self.state = .idle
        }

        if let root = root as? EasyNativeNavigationController,
           root.isPresentedFlow || root.presentingViewController != nil {
            root.dismiss(animated: true, completion: completion)
        } else {
            let popRoot = {
                if let flowRoot = self.flowRootViewController,
                   root.viewControllers.contains(where: { $0 === flowRoot }) {
                    root.popToViewController(flowRoot, animated: false)
                    root.popViewController(animated: true)
                }
                completion()
            }
            if root.presentedViewController != nil {
                root.dismiss(animated: false, completion: popRoot)
            } else {
                popRoot()
            }
        }
        EasyNativeLogger.log(.debug, "close native flow")
        return success(action: "closeNativeFlow")
    }

    public func clearIfActive(_ navigationController: EasyNativeNavigationController) {
        if flowRootNavigationController === navigationController {
            flowRootNavigationController = nil
            flowRootViewController = nil
            activeNavigationController = nil
            state = .idle
        } else if activeNavigationController === navigationController {
            activeNavigationController = currentNavigationController()
        }
    }

    public func handleNavigationStackChanged(_ navigationController: UINavigationController) {
        if navigationController === flowRootNavigationController,
           let flowRoot = flowRootViewController,
           !navigationController.viewControllers.contains(where: { $0 === flowRoot }) {
            clearState()
            return
        }

        if activeNavigationController === navigationController,
           navigationController.viewControllers.isEmpty {
            activeNavigationController = currentNavigationController()
        }
    }

    private func currentNavigationController() -> UINavigationController? {
        guard let root = flowRootNavigationController else {
            return activeNavigationController
        }

        var current: UINavigationController = root
        while let presented = current.presentedViewController as? EasyNativeNavigationController {
            current = presented
        }
        return current
    }

    private func attachRequestId(_ requestId: String?, to viewController: UIViewController) {
        guard let requestId = requestId, !requestId.isEmpty else { return }
        viewController.easyNativeRequestId = requestId
        viewController.easyNativeCompletionToken = EasyNativeRouteCompletionToken(requestId: requestId)
    }

    private func observeNavigationController(_ navigationController: UINavigationController) {
        let observer = navigationController.easyNativeNavigationObserver
            ?? EasyNativeNavigationObserver()
        navigationController.easyNativeNavigationObserver = observer
        observer.startObserving(navigationController)
    }

    public func completeRouteIfNeeded(_ viewController: UIViewController, result: Any?, action: String) {
        guard let requestId = viewController.easyNativeRequestId else { return }
        completeRoute(requestId: requestId, result: result, action: action)
    }

    public func completeRoute(requestId: String, result: Any?, action: String) {
        if action == "nativeDeinit" {
            let wasCompleted = completedRequestIds.contains(requestId)
            completedRequestIds.remove(requestId)
            if wasCompleted {
                return
            }
            EasyNativePlugin.completeRoute(requestId: requestId, result: result, action: action)
            return
        }

        guard !completedRequestIds.contains(requestId) else { return }
        completedRequestIds.insert(requestId)
        EasyNativePlugin.completeRoute(requestId: requestId, result: result, action: action)
    }

    private func completeActiveRoutes(result: Any?, action: String) {
        let controllers = activeFlowViewControllers().reversed()
        var deliveredResult = false
        controllers.forEach { viewController in
            let requestId = viewController.easyNativeRequestId
            completeRouteIfNeeded(
                viewController,
                result: !deliveredResult && requestId != nil ? result : nil,
                action: action
            )
            if requestId != nil {
                deliveredResult = true
            }
        }
    }

    private func activeFlowViewControllers() -> [UIViewController] {
        guard let root = flowRootNavigationController else { return [] }
        var controllers: [UIViewController] = []

        if let flowRoot = flowRootViewController,
           let index = root.viewControllers.firstIndex(of: flowRoot) {
            controllers.append(contentsOf: root.viewControllers.suffix(from: index))
        } else {
            controllers.append(contentsOf: root.viewControllers)
        }

        var current = root.presentedViewController as? EasyNativeNavigationController
        while let nav = current {
            controllers.append(contentsOf: nav.viewControllers)
            current = nav.presentedViewController as? EasyNativeNavigationController
        }

        return controllers
    }

    private func checkCanRoute(action: String) -> [String: Any]? {
        guard Thread.isMainThread else {
            return failure("Must be called from main thread", action: action)
        }
        if state == .closing {
            EasyNativeLogger.log(.warning, "reject \(action) while native flow is closing")
            return failure("Native flow is closing", action: action)
        }
        return nil
    }

    private func success(action: String, data: [String: Any]? = nil) -> [String: Any] {
        return [
            "success": true,
            "action": action,
            "data": data ?? [:],
        ]
    }

    private func failure(_ message: String, action: String) -> [String: Any] {
        return [
            "success": false,
            "action": action,
            "message": message,
        ]
    }
}
