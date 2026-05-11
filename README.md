# EasyNative

`easy_native` 是一个轻量级的 Flutter 混合路由插件。它专为“以 Flutter 为主，原生页面为辅”的项目设计。

它的核心理念非常简单且务实：**进入原生页面后，后续的路由堆栈交由原生端自行管理。本插件不试图维护像 FlutterBoost 极其复杂的双端混合栈状态映射。**

关于核心设计思路和接入指南，请参阅 [docs/design.md](docs/design.md)。

## 1. Flutter 端接入

在你的 Flutter 主入口进行初始化：

```dart
import 'package:easy_native/easy_native.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  EasyNative.init(
    modalRouteBuilder: (settings) {
      return CupertinoPageRoute(
        settings: settings,
        fullscreenDialog: true,
        builder: (_) => buildPage(settings.name, settings.arguments),
      );
    },
  );

  EasyNativeEventBus.initialize();
  EasyNativeMessenger.initialize();

  runApp(MaterialApp(
    navigatorKey: EasyNative.key,
    onGenerateRoute: onGenerateRoute,
  ));
}
```

## 2. 原生端接入配置

要让 `EasyNative` 能够顺利接管并执行原生路由流，你需要在 iOS 和 Android 的工程入口处进行极简的初始化配置。

### iOS 接入

在 iOS 中，Flutter 默认挂载在一个普通的 `FlutterViewController` 上。由于我们需要原生的堆栈能力，你必须手动将其包装进一个 `UINavigationController` 中，并提供给 `EasyNative`。

修改 `ios/Runner/AppDelegate.swift`：

```swift
import UIKit
import Flutter
import easy_native // 1. 引入插件

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private weak var hostNavigationController: UINavigationController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launchResult = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // 2. 将 FlutterViewController 包装进 UINavigationController 中
    if hostNavigationController == nil,
       let rootViewController = window?.rootViewController {
      let navigationController = UINavigationController(rootViewController: rootViewController)
      navigationController.isNavigationBarHidden = true
      hostNavigationController = navigationController
      window?.rootViewController = navigationController
      window?.makeKeyAndVisible()
    }

    // 3. 将 NavigationController 提供给 EasyNative
    EasyNative.shared.setup {
      self.hostNavigationController
    }

    // 4. 在此处注册你的原生路由...
    // EasyNative.shared.registerNativeRoute("/native/demo") { args in ... }

    return launchResult
  }
}
```

### Android 接入

在 Android 端，由于 `FlutterActivity` 已经提供了一个完整的 `Activity` 容器环境，你只需要在入口处初始化并传入 `Context` 即可。

修改 `android/app/src/main/kotlin/.../MainActivity.kt`：

```kotlin
import android.os.Bundle
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import com.example.easy_native.EasyNative // 1. 引入插件

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 2. 初始化 EasyNative
        EasyNative.setup(applicationContext)

        // 3. 在此处注册你的原生路由 Intent 映射...
        // EasyNative.registerNativeRoute("/native/demo") { context, args ->
        //     Intent(context, MyNativeActivity::class.java)
        // }
    }
}
```

## 3. 发起跨端路由

无论是跳转纯 Flutter 页面还是原生页面，现在你都可以通过一套统一的 API 闭着眼睛调用：

```dart
final result = await EasyNative.push('/native/detail', arguments: {
  'id': 1,
});

result.fold(
  (success) => debugPrint('路由成功: ${success.action}'),
  (failure) => debugPrint('路由失败: ${failure.message}'),
);
```

## 核心设计与混合路由语义

本插件不仅对基础的路由操作进行了双端拉平，还针对混合栈的特殊场景进行了语义上的纠正与增强：

1. **务实的混合栈模型**：
   - 当 `Flutter` 页面打开原生页面时，原生页面会覆盖在 `Flutter` 容器之上，开启原生路由流 (Native Flow)。
   - 原生路由流支持完整的 `push`、`present`、`replace`、`popUntil` 和 `pushAndRemoveUntil` 操作，全部交由底层的原生容器 (iOS `UINavigationController` / Android `Activity` 栈) 原生执行。

2. **跨端 `replace` 语义抹平**：
   - **Flutter 替换原生**：当原生流处于活跃状态时，如果你调用 `EasyNative.replace('flutter_route')`，插件会自动**关闭当前活动的原生流**，并在底层的 Flutter 栈上执行 `push` 操作。这保证了跨端替换时，新的 Flutter 页面能够正确叠加在旧的 Flutter 栈上，确保返回键状态和视觉语义前后一致。
   - **原生替换原生 / Flutter 替换 Flutter**：完全遵循各端自身的 `replace`（替换当前顶层页面）逻辑。

3. **双端生命周期自适应**：
   - **Android**：深度接入 `Activity` 的生命周期，支持物理返回键退出，精确追踪活跃的 Native Activity 栈。
   - **iOS**：深度适配 `UINavigationController`，完美支持原生左滑返回 (Swipe Back)。当用户通过手势或代码关闭最后一个原生页面时，自动感知并同步销毁跨端状态，防止状态残留。

## 核心 API

- `EasyNative.push`：压栈新页面（自动识别是 Flutter 还是 Native 路由）
- `EasyNative.replace`：替换当前顶层页面
- `EasyNative.present`：以模态 (Modal) 形式弹出页面
- `EasyNative.pushAndRemoveUntil`：压栈新页面并清空之前的指定历史栈
- `EasyNative.pop`：退栈
- `EasyNative.popUntil`：一直退栈直到指定页面
- `EasyNative.closeAll`：强制关闭当前所有活跃的原生页面
- `EasyNative.canPop`：判断当前混合栈是否可以后退
- `EasyNative.isNativeRoute`：判断目标路由是否已注册为原生路由
- `EasyNative.hasActiveNativeFlow`：判断当前是否有原生页面盖在 Flutter 之上

### 跨端通信与日志

除了核心的路由功能，插件还提供了轻量级的通信能力：
- **`EasyNativeMessenger`**：用于单次的跨端方法调用（封装 MethodCall）。
- **`EasyNativeEventBus`**：用于简单的 `type + data` 形式的事件流派发，适合处理跨界面的通知和数据同步。
- **`EasyNativeLogger`**：通过设置 `EasyNativeLogger.provider`，宿主 App 可以将内部路由日志重定向到自己的日志库中。

## 容错与超时策略

`easy_native` **不**对路由操作施加任何默认的超时（Timeout）。

路由方法代表着跨端的硬性协调，原生侧有责任必须回复所有的 MethodChannel 调用。如果原生侧没有回复，这被视为接入端的集成 Bug，应在原生代码中彻底修复。

插件底层仅捕获并转换异常为安全的 `ResultDart` 失败类型，绝不擅自自动重试或进行静默兜底，从而保证跨端状态机的一致性和确定性。
