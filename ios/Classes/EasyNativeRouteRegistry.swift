import UIKit

public final class EasyNativeRouteRegistry {
    public static let shared = EasyNativeRouteRegistry()

    private var nativeRoutes: [String: (Any?) -> UIViewController?] = [:]

    private init() {}

    public func registerNativeRoute(_ name: String, factory: @escaping (Any?) -> UIViewController?) {
        let routeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !routeName.isEmpty else {
            EasyNativeLogger.log(.warning, "ignore empty native route registration")
            return
        }
        if nativeRoutes[routeName] != nil {
            EasyNativeLogger.log(.warning, "override native route registration \(routeName)")
        } else {
            EasyNativeLogger.log(.info, "register native route \(routeName)")
        }
        nativeRoutes[routeName] = factory
    }

    public func isNativeRoute(_ name: String) -> Bool {
        return nativeRoutes[name] != nil
    }

    public func makeViewController(routeName: String, arguments: Any?) -> UIViewController? {
        guard let viewController = nativeRoutes[routeName]?(arguments) else {
            return nil
        }
        viewController.easyNativeRouteName = routeName
        viewController.easyNativeArguments = arguments
        return viewController
    }
}

private var easyNativeRouteNameKey: UInt8 = 0
private var easyNativeArgumentsKey: UInt8 = 0

extension UIViewController {
    public var easyNativeRouteName: String? {
        get {
            return objc_getAssociatedObject(self, &easyNativeRouteNameKey) as? String
        }
        set {
            objc_setAssociatedObject(
                self,
                &easyNativeRouteNameKey,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
        }
    }

    public var easyNativeArguments: Any? {
        get {
            return objc_getAssociatedObject(self, &easyNativeArgumentsKey)
        }
        set {
            objc_setAssociatedObject(
                self,
                &easyNativeArgumentsKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    public func easyNativeTopMost() -> UIViewController {
        if let presented = presentedViewController {
            return presented.easyNativeTopMost()
        }
        if let navigationController = self as? UINavigationController,
           let visible = navigationController.visibleViewController {
            return visible.easyNativeTopMost()
        }
        if let tabBarController = self as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return selected.easyNativeTopMost()
        }
        return self
    }
}
