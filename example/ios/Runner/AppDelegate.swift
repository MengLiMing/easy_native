import Flutter
import UIKit
import easy_native

@main
@objc class AppDelegate: FlutterAppDelegate {
  private weak var hostNavigationController: UINavigationController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launchResult = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if hostNavigationController == nil,
       let rootViewController = window?.rootViewController {
      let navigationController = UINavigationController(rootViewController: rootViewController)
      navigationController.isNavigationBarHidden = true
      hostNavigationController = navigationController
      window?.rootViewController = navigationController
      window?.makeKeyAndVisible()
    }

    EasyNative.shared.setup {
      self.hostNavigationController
    }

    ["/native/a", "/native/b", "/native/c"].forEach { route in
      EasyNative.shared.registerNativeRoute(route) { args in
        NativeDemoViewController(routeName: route, arguments: args)
      }
    }

    return launchResult
  }
}

final class NativeDemoViewController: UIViewController {
  private let routeName: String
  private let routeArguments: Any?

  init(routeName: String, arguments: Any?) {
    self.routeName = routeName
    self.routeArguments = arguments
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = backgroundColor()

    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)

    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(stack)

    let label = UILabel()
    label.numberOfLines = 0
    label.font = .systemFont(ofSize: 22, weight: .medium)
    label.text = "iOS native page\n\(routeName)\nargs: \(String(describing: routeArguments))"
    stack.addArrangedSubview(label)

    addButton("push /native/b", to: stack) {
      _ = EasyNative.shared.push("/native/b", arguments: ["from": self.routeName])
    }
    addButton("replace /native/c", to: stack) {
      _ = EasyNative.shared.replace("/native/c", arguments: ["from": self.routeName])
    }
    addButton("present /native/c", to: stack) {
      _ = EasyNative.shared.present("/native/c", arguments: ["from": self.routeName])
    }
    addButton("popUntil /native/a", to: stack) {
      _ = EasyNative.shared.popUntil("/native/a")
    }
    addButton("emit event: replace native c", to: stack) {
      EasyNativePlugin.emitToFlutter(type: "replaceNativeC", data: ["from": self.routeName])
    }
    addButton("emit event: replace flutter profile", to: stack) {
      EasyNativePlugin.emitToFlutter(type: "replaceFlutterProfile", data: ["from": self.routeName])
    }
    addButton("emit event: push flutter profile", to: stack) {
      EasyNativePlugin.emitToFlutter(type: "pushFlutterProfile", data: ["from": self.routeName])
    }
    addButton("emit event: popUntil flutter home", to: stack) {
      EasyNativePlugin.emitToFlutter(type: "popUntilFlutterHome", data: ["from": self.routeName])
    }
    addButton("pop", to: stack) {
      _ = EasyNative.shared.pop()
    }
    addButton("pop with result", to: stack) {
      _ = EasyNative.shared.pop(result: "iOS result from \(self.routeName)")
    }
    addButton("pop result int", to: stack) {
      _ = EasyNative.shared.pop(result: 7)
    }
    addButton("pop result bool", to: stack) {
      _ = EasyNative.shared.pop(result: true)
    }
    addButton("pop result list", to: stack) {
      _ = EasyNative.shared.pop(result: ["ios", self.routeName, 1, true])
    }
    addButton("pop result map", to: stack) {
      _ = EasyNative.shared.pop(result: [
        "platform": "ios",
        "route": self.routeName,
        "nested": ["ok": true],
        "items": [1, 2, 3]
      ])
    }
    addButton("close all native", to: stack) {
      _ = EasyNative.shared.closeAll()
    }
    addButton("close all native with result", to: stack) {
      _ = EasyNative.shared.closeAll(result: "iOS closeAll result from \(self.routeName)")
    }
    addButton("close all native with map result", to: stack) {
      _ = EasyNative.shared.closeAll(result: [
        "platform": "ios",
        "route": self.routeName,
        "action": "closeAll",
        "items": ["a", 1, true]
      ])
    }

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
    ])
  }

  private func addButton(_ title: String, to stack: UIStackView, action: @escaping () -> Void) {
    let button = ActionButton(type: .system)
    button.setTitle(title, for: .normal)
    button.action = action
    stack.addArrangedSubview(button)
  }

  private func backgroundColor() -> UIColor {
    switch routeName {
    case "/native/a":
      return UIColor(red: 0.82, green: 0.96, blue: 1.0, alpha: 1.0)
    case "/native/b":
      return UIColor(red: 0.86, green: 1.0, blue: 0.86, alpha: 1.0)
    default:
      return UIColor(red: 1.0, green: 0.92, blue: 0.82, alpha: 1.0)
    }
  }
}

final class ActionButton: UIButton {
  var action: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    addTarget(self, action: #selector(tap), for: .touchUpInside)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func tap() {
    action?()
  }
}
