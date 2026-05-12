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
  late bool autoCompleteNativeRoute;
  late String? closeAllCompletesRequestId;
  late Object? closeAllCompletionResult;
  late Object? nativeCompletionResult;

  setUp(() {
    navigatorKey = GlobalKey<NavigatorState>();
    EasyNative.init(key: navigatorKey, closeNativeFlowOnInit: false);
    EasyNativeLogger.enabled = false;
    calls = <MethodCall>[];
    activeNativeFlow = false;
    throwIsNativeRoute = false;
    closeAllFails = false;
    nativeRouteFails = false;
    autoCompleteNativeRoute = true;
    closeAllCompletesRequestId = null;
    closeAllCompletionResult = null;
    nativeCompletionResult = 'native-result';

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
          final requestId = closeAllCompletesRequestId;
          if (requestId != null) {
            Future<void>.microtask(
              () => _completeNativeRoute(requestId, closeAllCompletionResult),
            );
          }
          return <String, Object?>{
            'success': true,
            'action': call.method,
            'data': <String, Object?>{},
          };
        case 'push':
        case 'replace':
        case 'present':
        case 'pushAndRemoveUntil':
          if (nativeRouteFails) {
            return <String, Object?>{
              'success': false,
              'action': call.method,
              'message': 'native route failed',
            };
          }
          final args = call.arguments as Map<dynamic, dynamic>;
          final requestId = args['requestId'] as String?;
          if (requestId != null && autoCompleteNativeRoute) {
            Future<void>.microtask(
              () => _completeNativeRoute(requestId, nativeCompletionResult),
            );
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

    await expectLater(
      EasyNative.replace('/native/c'),
      throwsA(isA<EasyNativeRouteFailure>()),
    );
    await tester.pumpAndSettle();

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

    final result = await EasyNative.replace<String>('/native/c');
    await tester.pumpAndSettle();

    expect(result, 'native-result');
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

      final result = await EasyNative.pushAndRemoveUntil<String>(
        '/native/c',
        untilRoute: '/',
      );
      await tester.pumpAndSettle();

      expect(result, 'native-result');
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

    final result = await EasyNative.pushAndRemoveUntil<String>(
      '/native/c',
      untilRoute: '/',
    );
    await tester.pumpAndSettle();

    expect(result, 'native-result');
    expect(find.text('/'), findsOneWidget);
    expect(calls.map((call) => call.method), contains('pushAndRemoveUntil'));
  });

  testWidgets('push Flutter route inside native flow closes native first', (
    tester,
  ) async {
    activeNativeFlow = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final future = EasyNative.push<String>('/flutter/profile');
    await tester.pumpAndSettle();

    expect(find.text('/flutter/profile'), findsOneWidget);
    expect(
      calls.map((call) => call.method).toList(),
      containsAllInOrder(<String>['closeAll']),
    );

    navigatorKey.currentState!.pop('flutter-result');
    expect(await future, 'flutter-result');
  });

  testWidgets('does not continue Flutter route when closeAll fails', (
    tester,
  ) async {
    activeNativeFlow = true;
    closeAllFails = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    await expectLater(
      EasyNative.push('/flutter/profile'),
      throwsA(isA<EasyNativeRouteFailure>()),
    );
    await tester.pumpAndSettle();

    expect(find.text('/'), findsOneWidget);
    expect(calls.map((call) => call.method), contains('closeAll'));
  });

  testWidgets('closeAll forwards to native', (tester) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    await EasyNative.closeAll();

    expect(calls.map((call) => call.method), contains('closeAll'));
  });

  testWidgets('closeAll result completes pending native push future', (
    tester,
  ) async {
    autoCompleteNativeRoute = false;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final nativeFuture = EasyNative.push<String>('/native/a');
    await tester.pump();

    final pushCall = calls.singleWhere((call) => call.method == 'push');
    final pushArgs = pushCall.arguments as Map<dynamic, dynamic>;
    closeAllCompletesRequestId = pushArgs['requestId'] as String?;
    closeAllCompletionResult = 'close-all-result';

    await EasyNative.closeAll('close-all-result');

    expect(await nativeFuture, 'close-all-result');
    expect(calls.map((call) => call.method), contains('closeAll'));
  });

  testWidgets('popUntil Flutter route keeps Navigator semantics', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final future = EasyNative.push<String>('/flutter/profile');
    await tester.pumpAndSettle();
    expect(find.text('/flutter/profile'), findsOneWidget);

    await EasyNative.popUntil('/');
    await tester.pumpAndSettle();

    expect(find.text('/'), findsOneWidget);
    expect(await future, isNull);
  });

  testWidgets('popUntil missing Flutter route falls back to first route', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final future = EasyNative.push<String>('/flutter/profile');
    await tester.pumpAndSettle();
    expect(find.text('/flutter/profile'), findsOneWidget);

    await EasyNative.popUntil('/missing');
    await tester.pumpAndSettle();

    expect(find.text('/'), findsOneWidget);
    expect(await future, isNull);
  });

  testWidgets('native map result is normalized for typed await', (
    tester,
  ) async {
    nativeCompletionResult = <Object?, Object?>{
      'id': 1,
      'nested': <Object?, Object?>{'ok': true},
      'items': <Object?>[
        <Object?, Object?>{'name': 'a'},
      ],
    };
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    final result = await EasyNative.push<Map<String, dynamic>>(
      '/native/detail',
    );

    expect(result?['id'], 1);
    expect(result?['nested'], isA<Map<String, dynamic>>());
    expect(result?['nested']['ok'], isTrue);
    expect(result?['items'], isA<List<Object?>>());
    expect(result?['items'][0], isA<Map<String, dynamic>>());
    expect(result?['items'][0]['name'], 'a');
  });

  for (final scenario in <({String name, Object? value})>[
    (name: 'null', value: null),
    (name: 'string', value: 'native string'),
    (name: 'int', value: 7),
    (name: 'double', value: 3.5),
    (name: 'bool', value: true),
    (name: 'list', value: <Object?>['a', 1, true, null]),
    (
      name: 'nested list and map',
      value: <Object?, Object?>{
        'items': <Object?>[
          <Object?, Object?>{'id': 1},
          <Object?, Object?>{'id': 2},
        ],
      },
    ),
  ]) {
    testWidgets('native ${scenario.name} result round trips', (tester) async {
      nativeCompletionResult = scenario.value;
      await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

      final result = await EasyNative.push<Object?>('/native/detail');

      expect(result, _normalizedValue(scenario.value));
    });
  }

  testWidgets('route failure throws EasyNativeRouteFailure', (tester) async {
    throwIsNativeRoute = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    await expectLater(
      EasyNative.push('/native/detail'),
      throwsA(isA<EasyNativeRouteFailure>()),
    );
  });

  testWidgets('core route fails when isNativeRoute channel throws', (
    tester,
  ) async {
    throwIsNativeRoute = true;
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    await expectLater(
      EasyNative.push('/flutter/profile'),
      throwsA(isA<EasyNativeRouteFailure>()),
    );
    await tester.pumpAndSettle();

    expect(find.text('/'), findsOneWidget);
  });

  testWidgets('non serializable arguments throw failure', (tester) async {
    await tester.pumpWidget(_TestApp(navigatorKey: navigatorKey));

    await expectLater(
      EasyNative.push(
        '/native/detail',
        arguments: <String, Object?>{'value': Object()},
      ),
      throwsA(isA<EasyNativeRouteFailure>()),
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

Object? _normalizedValue(Object? value) {
  if (value is Map) {
    return value.map<String, Object?>(
      (key, item) => MapEntry(key.toString(), _normalizedValue(item)),
    );
  }
  if (value is List) {
    return value.map(_normalizedValue).toList();
  }
  return value;
}

Future<void> _completeNativeRoute(String requestId, Object? result) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final data = const StandardMethodCodec().encodeMethodCall(
    MethodCall('completeRoute', <String, Object?>{
      'requestId': requestId,
      'result': result,
      'success': true,
      'action': 'nativePop',
    }),
  );
  await messenger.handlePlatformMessage('easy_native/router', data, (_) {});
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
