import Flutter
import UIKit

public final class EasyNative {
    public static let shared = EasyNative()

    public var rootNavigatorProvider: (() -> UINavigationController?)?

    private init() {}

    public func setup(rootNavigatorProvider: @escaping () -> UINavigationController?) {
        self.rootNavigatorProvider = rootNavigatorProvider
    }

    public func setLogProvider(_ provider: EasyNativeLogger.Provider?) {
        EasyNativeLogger.provider = provider
    }

    public func registerNativeRoute(_ name: String, factory: @escaping (Any?) -> UIViewController?) {
        EasyNativeRouteRegistry.shared.registerNativeRoute(name, factory: factory)
    }

    public func registerNativeMethod(
        _ method: String,
        handler: @escaping (Any?, @escaping FlutterResult) -> Void
    ) {
        EasyNativePlugin.shared?.registerNativeMethod(method, handler: handler)
    }

    public func registerNativeEventHandler(_ handler: @escaping (String, Any?) -> Void) {
        EasyNativePlugin.shared?.registerNativeEventHandler(handler)
    }

    public func push(_ routeName: String, arguments: Any? = nil) -> [String: Any] {
        return EasyNativeFlowManager.shared.push(
            routeName: routeName,
            arguments: arguments,
            from: rootNavigatorProvider?(),
            requestId: nil
        )
    }

    public func replace(_ routeName: String, arguments: Any? = nil) -> [String: Any] {
        if EasyNativeFlowManager.shared.hasActiveNativeFlow {
            return EasyNativeFlowManager.shared.replace(
                routeName: routeName,
                arguments: arguments,
                result: nil,
                requestId: nil
            )
        }
        return EasyNativeFlowManager.shared.push(
            routeName: routeName,
            arguments: arguments,
            from: rootNavigatorProvider?(),
            requestId: nil
        )
    }

    public func present(_ routeName: String, arguments: Any? = nil) -> [String: Any] {
        return EasyNativeFlowManager.shared.present(
            routeName: routeName,
            arguments: arguments,
            from: rootNavigatorProvider?(),
            requestId: nil
        )
    }

    public func pop(result: Any? = nil) -> [String: Any] {
        return EasyNativeFlowManager.shared.pop(result: result)
    }

    public func popUntil(_ routeName: String) -> [String: Any] {
        return EasyNativeFlowManager.shared.popUntil(routeName: routeName)
    }

    public func closeAll(result: Any? = nil) -> [String: Any] {
        return EasyNativeFlowManager.shared.closeAll(result: result)
    }
}

public final class EasyNativePlugin: NSObject, FlutterPlugin {
    private var routerChannel: FlutterMethodChannel?
    private var eventChannel: FlutterMethodChannel?
    private var methodChannel: FlutterMethodChannel?
    private var nativeMethodHandlers: [String: (Any?, @escaping FlutterResult) -> Void] = [:]
    private var nativeEventHandlers: [(String, Any?) -> Void] = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = EasyNativePlugin()
        instance.routerChannel = FlutterMethodChannel(
            name: "easy_native/router",
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel = FlutterMethodChannel(
            name: "easy_native/event_bus",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = FlutterMethodChannel(
            name: "easy_native/methods",
            binaryMessenger: registrar.messenger()
        )

        registrar.addMethodCallDelegate(instance, channel: instance.routerChannel!)
        registrar.addMethodCallDelegate(instance, channel: instance.eventChannel!)
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)
        EasyNativePlugin.shared = instance
    }

    fileprivate static weak var shared: EasyNativePlugin?

    public static func emitToFlutter(type: String, data: Any? = nil) {
        shared?.eventChannel?.invokeMethod("emitToFlutter", arguments: [
            "type": type,
            "data": data ?? NSNull(),
        ])
    }

    public static func invokeFlutter(method: String, data: Any? = nil, result: FlutterResult? = nil) {
        shared?.methodChannel?.invokeMethod(
            "invokeFlutter",
            arguments: [
                "method": method,
                "data": data ?? NSNull(),
            ],
            result: result
        )
    }

    public static func completeRoute(
        requestId: String,
        result: Any? = nil,
        action: String = "nativeRouteComplete"
    ) {
        shared?.routerChannel?.invokeMethod("completeRoute", arguments: [
            "requestId": requestId,
            "result": result ?? NSNull(),
            "success": true,
            "action": action,
        ])
    }

    public func registerNativeMethod(
        _ method: String,
        handler: @escaping (Any?, @escaping FlutterResult) -> Void
    ) {
        let methodName = method.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !methodName.isEmpty else {
            EasyNativeLogger.log(.warning, "ignore empty native method registration")
            return
        }
        if nativeMethodHandlers[methodName] != nil {
            EasyNativeLogger.log(.warning, "override native method registration \(methodName)")
        }
        nativeMethodHandlers[methodName] = handler
    }

    public func registerNativeEventHandler(_ handler: @escaping (String, Any?) -> Void) {
        nativeEventHandlers.append(handler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        EasyNativeLogger.log(.debug, "method call \(call.method)")
        switch call.method {
        case "isNativeRoute":
            let args = call.arguments as? [String: Any] ?? [:]
            result(EasyNativeRouteRegistry.shared.isNativeRoute(args["routeName"] as? String ?? ""))
        case "hasActiveNativeFlow":
            result(EasyNativeFlowManager.shared.hasActiveNativeFlow)
        case "push":
            result(route(arguments: call.arguments, action: .push))
        case "replace":
            result(route(arguments: call.arguments, action: .replace))
        case "present":
            result(route(arguments: call.arguments, action: .present))
        case "pop":
            let args = call.arguments as? [String: Any] ?? [:]
            result(EasyNativeFlowManager.shared.pop(result: args["result"]))
        case "popUntil":
            let args = call.arguments as? [String: Any] ?? [:]
            result(EasyNativeFlowManager.shared.popUntil(routeName: args["routeName"] as? String ?? ""))
        case "pushAndRemoveUntil":
            result(route(arguments: call.arguments, action: .pushAndRemoveUntil))
        case "closeAll":
            let args = call.arguments as? [String: Any] ?? [:]
            result(EasyNativeFlowManager.shared.closeAll(result: args["result"]))
        case "emitToNative":
            let args = call.arguments as? [String: Any] ?? [:]
            let type = args["type"] as? String ?? ""
            let data = args["data"]
            nativeEventHandlers.forEach { $0(type, data) }
            result(true)
        case "invokeNative":
            let args = call.arguments as? [String: Any] ?? [:]
            let method = (args["method"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let handler = nativeMethodHandlers[method] {
                handler(args["data"], result)
            } else {
                result(FlutterMethodNotImplemented)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private enum NativeRouteAction {
        case push
        case replace
        case present
        case pushAndRemoveUntil
    }

    private func route(arguments: Any?, action: NativeRouteAction) -> [String: Any] {
        let args = arguments as? [String: Any] ?? [:]
        let routeName = args["routeName"] as? String ?? ""
        switch action {
        case .push:
            return EasyNativeFlowManager.shared.push(
                routeName: routeName,
                arguments: args["arguments"],
                from: EasyNative.shared.rootNavigatorProvider?(),
                requestId: args["requestId"] as? String
            )
        case .replace:
            if EasyNativeFlowManager.shared.hasActiveNativeFlow {
                return EasyNativeFlowManager.shared.replace(
                    routeName: routeName,
                    arguments: args["arguments"],
                    result: args["result"],
                    requestId: args["requestId"] as? String
                )
            }
            return EasyNativeFlowManager.shared.push(
                routeName: routeName,
                arguments: args["arguments"],
                from: EasyNative.shared.rootNavigatorProvider?(),
                requestId: args["requestId"] as? String
            )
        case .present:
            return EasyNativeFlowManager.shared.present(
                routeName: routeName,
                arguments: args["arguments"],
                from: EasyNative.shared.rootNavigatorProvider?(),
                requestId: args["requestId"] as? String
            )
        case .pushAndRemoveUntil:
            if EasyNativeFlowManager.shared.hasActiveNativeFlow {
                return EasyNativeFlowManager.shared.pushAndRemoveUntil(
                    routeName: routeName,
                    arguments: args["arguments"],
                    untilRoute: args["untilRoute"] as? String,
                    requestId: args["requestId"] as? String
                )
            }
            return EasyNativeFlowManager.shared.push(
                routeName: routeName,
                arguments: args["arguments"],
                from: EasyNative.shared.rootNavigatorProvider?(),
                requestId: args["requestId"] as? String
            )
        }
    }
}
