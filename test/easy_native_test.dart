import 'package:easy_native/easy_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const routerChannel = MethodChannel('easy_native/router');

  late GlobalKey<NavigatorState> navigatorKey;
  late List<MethodCall> calls;
  late bool activeNativeFlow;
  late bool throwIsNativeRoute;
  late bool closeAllFails;
  late bool nativeRouteFails;

  setUp(() {
    navigatorKey = GlobalKey<NavigatorState>();
    EasyNative.init(key: navigatorKey, closeNativeFlowOnInit: false);
    EasyNativeLogger.enabled = false;
    calls = <MethodCall>[];
    activeNativeFlow = false;
    throwIsNativeRoute = false;
    closeAllFails = false;
    nativeRouteFails = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(routerChannel, (MethodCall call) async {
          calls.add(call);
          switch (call.method) {
            case 'isNativeRoute':
              if (throwIsNativeRoute) {
                throw PlatformException(
                  code: 'is_native_failed',
                  message: 'isNativeRoute failed',
                );
              }
              final args = call.arguments as Map<dynamic, dynamic>;
              return (args['routeName'] as String).startsWith('/native/');
            case 'hasActiveNativeFlow':
              return activeNativeFlow;
            case 'closeAll':
              if (closeAllFails) {
                return <String, Object?>{
                  'success': false,
                  'action': call.method,
                  'message': 'closeAll failed',
                };
              }
              return <String, Object?>{
                'success': true,
                'action': call.method,
                'data': <String, Object?>{},
              };
            case 'push':
            case 'replace':
            case 'pushAndRemoveUntil':
              if (nativeRouteFails) {
                return <String, Object?>{
                  'success': false,
                  'action': call.method,
                  'message': 'native route failed',
                };
              }
              return <String, Object?>{
                'success': true,
                'action': call.method,
                'data': <String, Object?>{},
              };
            default:
              return <String, Object?>{
                'success': false,
                'action': call.method,
                'message': 'Unhandled test method',
              };
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(routerChannel, null);
    EasyNativeLogger.enabled = true;
  });

  testWidgets('native replace does not pop Flutter before native succeeds', (
    tester,
  ) async {
    nativeRouteFails = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    navigatorKey.currentState!.pushNamed('/flutter/list');
    await tester.pumpAndSettle();
    expect(find.text('/flutter/list'), findsOneWidget);

    final result = await EasyNative.replace('/native/c');
    await tester.pumpAndSettle();

    expect(result.isError(), isTrue);
    expect(find.text('/flutter/list'), findsOneWidget);
    expect(calls.map((call) => call.method), contains('replace'));
  });

  testWidgets('native replace removes current Flutter route after success', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    navigatorKey.currentState!.pushNamed('/flutter/list');
    await tester.pumpAndSettle();
    expect(find.text('/flutter/list'), findsOneWidget);

    final result = await EasyNative.replace('/native/c');
    await tester.pumpAndSettle();

    expect(result.isSuccess(), isTrue);
    expect(find.text('/'), findsOneWidget);
    expect(calls.map((call) => call.method), contains('replace'));
  });

  testWidgets(
    'pushAndRemoveUntil native inside native flow does not pop Flutter',
    (tester) async {
      activeNativeFlow = true;
      await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

      navigatorKey.currentState!.pushNamed('/flutter/list');
      await tester.pumpAndSettle();

      final result = await EasyNative.pushAndRemoveUntil(
        '/native/c',
        untilRoute: '/',
      );
      await tester.pumpAndSettle();

      expect(result.isSuccess(), isTrue);
      expect(find.text('/flutter/list'), findsOneWidget);
      expect(calls.map((call) => call.method), contains('pushAndRemoveUntil'));
    },
  );

  testWidgets('pushAndRemoveUntil native from Flutter syncs Flutter stack', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    navigatorKey.currentState!.pushNamed('/flutter/list');
    await tester.pumpAndSettle();
    expect(find.text('/flutter/list'), findsOneWidget);

    final result = await EasyNative.pushAndRemoveUntil(
      '/native/c',
      untilRoute: '/',
    );
    await tester.pumpAndSettle();

    expect(result.isSuccess(), isTrue);
    expect(find.text('/'), findsOneWidget);
    expect(calls.map((call) => call.method), contains('pushAndRemoveUntil'));
  });

  testWidgets('push Flutter route inside native flow closes native first', (
    tester,
  ) async {
    activeNativeFlow = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final result = await EasyNative.push('/flutter/profile');
    await tester.pumpAndSettle();

    expect(result.isSuccess(), isTrue);
    expect(find.text('/flutter/profile'), findsOneWidget);
    expect(
      calls.map((call) => call.method).toList(),
      containsAllInOrder(<String>['closeAll']),
    );
  });

  testWidgets('does not continue Flutter route when closeAll fails', (
    tester,
  ) async {
    activeNativeFlow = true;
    closeAllFails = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final result = await EasyNative.push('/flutter/profile');
    await tester.pumpAndSettle();

    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull()?.action, 'closeAll');
    expect(find.text('/'), findsOneWidget);
    expect(calls.map((call) => call.method), contains('closeAll'));
  });

  testWidgets('closeAll forwards to native and returns result', (tester) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final result = await EasyNative.closeAll();

    expect(result.isSuccess(), isTrue);
    expect(result.getOrNull()?.action, 'closeAll');
    expect(calls.map((call) => call.method), contains('closeAll'));
  });

  testWidgets('popUntil missing Flutter route does not blank the navigator', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final replaceResult = await EasyNative.replace('/flutter/profile');
    await tester.pumpAndSettle();
    expect(replaceResult.isSuccess(), isTrue);
    expect(find.text('/flutter/profile'), findsOneWidget);

    final result = await EasyNative.popUntil('/');
    await tester.pumpAndSettle();

    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull()?.action, 'flutterPopUntil');
    expect(find.text('/flutter/profile'), findsOneWidget);
  });

  testWidgets('route failure should not throw outside ResultDart', (
    tester,
  ) async {
    throwIsNativeRoute = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final result = await EasyNative.push('/native/detail');

    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull()?.message, contains('PlatformException'));
  });

  testWidgets('core route fails when isNativeRoute channel throws', (
    tester,
  ) async {
    throwIsNativeRoute = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final result = await EasyNative.push('/flutter/profile');
    await tester.pumpAndSettle();

    expect(result.isError(), isTrue);
    expect(find.text('/'), findsOneWidget);
  });

  testWidgets('non serializable arguments return Failure', (tester) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final result = await EasyNative.push(
      '/native/detail',
      arguments: <String, Object?>{'value': Object()},
    );

    expect(result.isError(), isTrue);
    expect(
      result.exceptionOrNull()?.message,
      contains('Cross-end arguments must be JSON serializable'),
    );
    expect(calls, isEmpty);
  });

  test('event bus and messenger initialize are idempotent', () {
    EasyNativeEventBus.initialize();
    EasyNativeEventBus.initialize();
    EasyNativeMessenger.initialize();
    EasyNativeMessenger.initialize();

    expect(
      () => EasyNativeMessenger.registerFlutterMethod(' ', (_) async => null),
      throwsArgumentError,
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      onGenerateRoute: (settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              Scaffold(body: Center(child: Text(settings.name ?? '/'))),
        );
      },
    );
  }
}
