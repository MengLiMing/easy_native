import UIKit

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

/// Coordinates a native flow. It is not a stack manager; UIKit owns the real stack.
public final class EasyNativeFlowManager {
    public static let shared = EasyNativeFlowManager()

    private weak var flowRootNavigationController: UINavigationController?
    private weak var flowRootViewController: UIViewController?
    private weak var activeNavigationController: UINavigationController?
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
        from rootNav: UINavigationController?
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

        if let active = currentNavigationController() {
            EasyNativeLogger.log(.debug, "native push \(routeName)")
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
        rootNav.pushViewController(viewController, animated: true)
        return success(action: "openNativeFlow")
    }

    public func present(
        routeName: String,
        arguments: Any?,
        from rootNav: UINavigationController?
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

        let container = EasyNativeNavigationController(rootViewController: viewController)
        container.isNavigationBarHidden = true
        container.isPresentedFlow = true
        container.modalPresentationStyle = .fullScreen

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

    public func replace(routeName: String, arguments: Any?) -> [String: Any] {
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
                active.dismiss(animated: true) {
                    self.activeNavigationController = self.currentNavigationController()
                }
                EasyNativeLogger.log(.debug, "native dismiss presented flow")
                return success(action: "nativeDismiss")
            }
            return closeAll(result: result)
        }

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
        active.popToViewController(target, animated: true)
        EasyNativeLogger.log(.debug, "native popUntil \(routeName)")
        return success(action: "nativePopUntil")
    }

    public func pushAndRemoveUntil(
        routeName: String,
        arguments: Any?,
        untilRoute: String?
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
        guard let active = currentNavigationController() else {
            return failure("No active native flow", action: "nativePushAndRemoveUntil")
        }

        var stack = active.viewControllers
        var removedFlowRoot = false

        if let untilRoute = untilRoute,
           let index = stack.lastIndex(where: { $0.easyNativeRouteName == untilRoute }) {
            let toRemove = stack.suffix(from: index + 1)
            if toRemove.contains(where: { $0 === flowRootViewController }) {
                removedFlowRoot = true
            }
            stack = Array(stack.prefix(index + 1))
        } else {
            if active === flowRootNavigationController, let flowRoot = flowRootViewController, let index = stack.firstIndex(of: flowRoot) {
                stack = Array(stack.prefix(index))
                removedFlowRoot = true
            } else {
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
