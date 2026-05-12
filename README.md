# EasyNative

`easy_native` 是一个面向 Flutter 混编项目的轻量级统一路由插件，适用于 **Flutter 为主、原生页面为辅** 的项目。

核心原则：

> Flutter 负责 Flutter 栈内的页面流转。  
> 当 Flutter 跳转到 Native 后，会进入一个 Native Flow。  
> Native Flow 内的后续 `push / pop / replace / popUntil / pushAndRemoveUntil` 都交由原生栈自行管理。  
> iOS 由 `UINavigationController` 管理 Native Flow，Android 由系统 `Activity` 栈管理 Native Flow。  
> EasyNative 只负责 Flutter 与 Native 边界处的路由协调，不维护 Flutter / Native 混合虚拟栈。

---

## 特性

- 一套 API 同时跳转 Flutter 页面和 Native 页面
- Flutter 跳转到 Native 后，后续 Native Flow 由原生栈接管
- API 语义对齐 Flutter `Navigator`
- `push / present / replace / pushAndRemoveUntil` 会在页面关闭后返回结果
- 支持 Native `popUntil`
- 支持跨端 Method 调用和 Event 事件通信
- 支持自定义日志接入
- 不做 FlutterBoost 式复杂混合栈同步

## Flutter 接入

```dart
import 'package:easy_native/easy_native.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  EasyNative.init(
    // 使用 Navigator 1.0 时可传入 modalRouteBuilder
    // modalRouteBuilder: (settings) => CupertinoPageRoute(...),

    // 使用 go_router / auto_route / 自研路由时可传入 flutterRouter
    // flutterRouter: MyFlutterRouter(),
  );

  runApp(MaterialApp(
    navigatorKey: EasyNative.key,
    onGenerateRoute: onGenerateRoute,
  ));
}
```

`EasyNative.init()` 会自动初始化：

```dart
EasyNativeEventBus.initialize();
EasyNativeMessenger.initialize();
```

业务侧通常不需要手动调用。

---

## iOS 接入

iOS 侧需要提供一个宿主 `UINavigationController`。

```swift
import UIKit
import Flutter
import easy_native

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private weak var hostNavigationController: UINavigationController?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let launchResult = super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        if hostNavigationController == nil,
           let rootViewController = window?.rootViewController {
            let navigationController = UINavigationController(
                rootViewController: rootViewController
            )
            navigationController.isNavigationBarHidden = true
            hostNavigationController = navigationController
            window?.rootViewController = navigationController
            window?.makeKeyAndVisible()
        }

        EasyNative.shared.setup {
            self.hostNavigationController
        }

        EasyNative.shared.registerNativeRoute("/native/detail") { args in
            NativeDetailViewController(arguments: args)
        }

        return launchResult
    }
}
```

---

## Android 接入

```kotlin
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import com.example.easy_native.EasyNative

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        EasyNative.setup(applicationContext)

        EasyNative.registerNativeRoute("/native/detail") { context, args ->
            Intent(context, NativeDetailActivity::class.java)
        }
    }
}
```

> `com.example.easy_native` 请替换为插件实际包名。

---

## 基础路由

### push

```dart
final result = await EasyNative.push<String>(
  '/native/detail',
  arguments: {'id': 1},
);

print(result);
```

### replace

```dart
final result = await EasyNative.replace<String>(
  '/native/detail',
  arguments: {'id': 1},
);
```

### present

```dart
final result = await EasyNative.present<String>(
  '/native/modal',
  arguments: {'from': 'flutter'},
);
```

### pushAndRemoveUntil

```dart
final result = await EasyNative.pushAndRemoveUntil<String>(
  '/native/detail',
  arguments: {'id': 1},
  untilRoute: '/',
);
```

### pop

```dart
await EasyNative.pop({'success': true});
```

### popUntil

```dart
await EasyNative.popUntil('/native/detail');
```

### closeAll

```dart
await EasyNative.closeAll();
```

---

## Native 页面返回结果

### Flutter

```dart
await EasyNative.pop({'success': true});
```

### iOS

```swift
EasyNative.shared.pop(result: ["success": true])
```

### Android

```kotlin
EasyNative.pop(mapOf("success" to true))
```

---

## 混合路由语义

### Flutter -> Native

Flutter 页面打开 Native 页面时，Native 页面覆盖在 Flutter 容器之上，开启 Native Flow。

```text
Flutter /
Flutter /list
  -> EasyNative.push('/native/detail')
  -> Native /native/detail
```

### Native -> Flutter

当 Native Flow 活跃时跳转 Flutter 页面，EasyNative 会先关闭当前 Native Flow，再执行 Flutter 路由。

### Flutter replace Native

```text
Flutter /
Flutter /list
  -> EasyNative.replace('/native/detail')
  -> Native 打开成功后，Flutter /list 被移除
  -> Native 关闭后回到 Flutter /
```

如果希望保留当前 Flutter 页面，请使用 `push`。

### Native popUntil

```text
Native A
Native B
Native C
  -> EasyNative.popUntil('/native/a')
  -> 关闭 B / C
  -> 停留在 A
```

---

## Native Flow Manager

`EasyNativeFlowManager` 不是栈管理器。

真实栈由平台自己管理：

| 平台    | 真实栈                 |
| ------- | ---------------------- |
| Flutter | Navigator              |
| iOS     | UINavigationController |
| Android | Activity 栈            |

EasyNative 只负责：

- 判断 Native Flow 是否活跃
- 转发跨端路由请求
- 记录页面 route tag
- 在页面关闭时完成 Dart Future
- 支持 `popUntil`

EasyNative 不维护 Flutter / Native 混合虚拟栈，也不暴露 native stack depth。

---

## Route Tag

每个通过 EasyNative 创建的 Native 页面都会自动携带 route tag：

| 平台    | tag                                                      |
| ------- | -------------------------------------------------------- |
| iOS     | `UIViewController.easyNativeRouteName`                   |
| Android | `Intent` 中的 `EasyNativeRouteRegistry.EXTRA_ROUTE_NAME` |

`popUntil` 依赖 route tag 查找目标页面。

如果 Native 内部使用系统原生跳转，也可以手动设置 route tag。

### iOS

```swift
let vc = NativeDetailViewController()
vc.easyNativeRouteName = "/native/detail"
navigationController?.pushViewController(vc, animated: true)
```

### Android

```kotlin
val intent = Intent(this, NativeDetailActivity::class.java)
intent.putExtra(EasyNativeRouteRegistry.EXTRA_ROUTE_NAME, "/native/detail")
startActivity(intent)
```

---

## Native 内部普通跳转

Native Flow 内部允许使用系统导航：

```swift
navigationController?.pushViewController(viewController, animated: true)
```

```kotlin
startActivity(Intent(this, DetailActivity::class.java))
```

但需要注意：

- 普通系统跳转不会自动参与 EasyNative 的 route lifecycle；
- 需要被 `popUntil` 找到时，需要手动设置 route tag；
- 需要统一返回值、日志、注册校验时，建议使用 EasyNative 原生 API。

---

## 异常策略

Public API 使用 Flutter 风格：

```dart
try {
  final result = await EasyNative.push('/native/detail');
} on EasyNativeRouteFailure catch (e) {
  print(e.message);
}
```

失败时抛出 `EasyNativeRouteFailure`。

---

## 跨端通信

### EasyNativeMessenger

Flutter 注册方法供 Native 调用：

```dart
EasyNativeMessenger.registerFlutterMethod('getUserInfo', (data) async {
  return {'name': 'Flutter User'};
});
```

Flutter 调用 Native 方法：

```dart
final result = await EasyNativeMessenger.invokeNative<Map>(
  'getDeviceInfo',
  data: {'from': 'flutter'},
);
```

### EasyNativeEventBus

Flutter 监听 Native 事件：

```dart
final subscription = EasyNativeEventBus.nativeEvents.listen((event) {
  print(event.type);
  print(event.data);
});
```

Flutter 发送事件给 Native：

```dart
await EasyNativeEventBus.emitToNative(
  'refreshDevice',
  data: {'id': 1},
);
```

---

## 日志

```dart
EasyNative.init(
  logProvider: (
    level,
    message, {
    error,
    stackTrace,
  }) {
    print('[EasyNative][$level] $message');
  },
);
```

关闭日志：

```dart
EasyNativeLogger.enabled = false;
```

---

## API 概览

| API                                | 说明                                      |
| ---------------------------------- | ----------------------------------------- |
| `EasyNative.push<T>`               | 打开页面，页面关闭后返回结果              |
| `EasyNative.replace<T>`            | 替换页面，页面关闭后返回结果              |
| `EasyNative.present<T>`            | 以 modal 语义打开页面，页面关闭后返回结果 |
| `EasyNative.pushAndRemoveUntil<T>` | 打开页面并清理历史栈，页面关闭后返回结果  |
| `EasyNative.pop`                   | 关闭当前页面并传递 result                 |
| `EasyNative.popUntil`              | 回退到指定 route                          |
| `EasyNative.closeAll`              | 关闭当前完整 Native Flow                  |
| `EasyNative.canPop`                | 判断当前是否可以返回                      |
| `EasyNative.isNativeRoute`         | 判断 route 是否为 Native route            |
| `EasyNative.hasActiveNativeFlow`   | 判断当前是否存在 Native Flow              |

---

## License

MIT
