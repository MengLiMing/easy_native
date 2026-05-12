part of easy_native;

abstract class EasyNativeSerializable {
  Map<String, dynamic> toJson();
}

enum EasyNativeLogLevel { debug, info, warning, error }

typedef EasyNativeLogProvider = void Function(
  EasyNativeLogLevel level,
  String message, {
  Object? error,
  StackTrace? stackTrace,
});

class EasyNativeLogger {
  EasyNativeLogger._();

  static EasyNativeLogProvider? provider;
  static bool enabled = true;

  static void log(
    EasyNativeLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled) return;
    final customProvider = provider;
    if (customProvider != null) {
      customProvider(level, message, error: error, stackTrace: stackTrace);
      return;
    }
    debugPrint('[EasyNative][${level.name}] $message');
    if (error != null) {
      debugPrint('[EasyNative][${level.name}] error: $error');
    }
    if (stackTrace != null) {
      debugPrint('[EasyNative][${level.name}] stackTrace: $stackTrace');
    }
  }
}

class EasyNativeRouteFailure implements Exception {
  const EasyNativeRouteFailure(this.message, {this.action});

  final String message;
  final String? action;

  @override
  String toString() {
    if (action == null) return 'EasyNativeRouteFailure($message)';
    return 'EasyNativeRouteFailure($action: $message)';
  }
}

enum EasyNativeRouteAction {
  push,
  replace,
  present,
  pop,
  popUntil,
  pushAndRemoveUntil,
}

class _PendingNativeRoute {
  _PendingNativeRoute(this.completer);

  final Completer<Object?> completer;
}

typedef EasyNativeModalRouteBuilder = Route<T> Function<T>(
    RouteSettings settings);

abstract class EasyNativeFlutterRouter {
  Future<Object?> push(String routeName, {Object? arguments});
  Future<Object?> replace(String routeName,
      {Object? arguments, Object? result});
  Future<Object?> present(String routeName, {Object? arguments});
  Future<void> pop<T extends Object?>([T? result]);
  Future<void> popUntil(String routeName);
  Future<Object?> pushAndRemoveUntil(String routeName,
      {Object? arguments, required String untilRoute});
  bool canPop();
}

class EasyNativeDefaultFlutterRouter implements EasyNativeFlutterRouter {
  final GlobalKey<NavigatorState> navigatorKey;
  final EasyNativeModalRouteBuilder? modalRouteBuilder;

  EasyNativeDefaultFlutterRouter(this.navigatorKey, {this.modalRouteBuilder});

  NavigatorState get _navigator {
    final state = navigatorKey.currentState;
    assert(state != null,
        'EasyNative: navigatorKey is not attached to a Navigator.');
    return state!;
  }

  @override
  Future<Object?> push(String routeName, {Object? arguments}) {
    return _navigator.pushNamed<Object?>(routeName, arguments: arguments);
  }

  @override
  Future<Object?> replace(String routeName,
      {Object? arguments, Object? result}) {
    return _navigator.pushReplacementNamed<Object?, Object?>(routeName,
        arguments: arguments, result: result);
  }

  @override
  Future<Object?> present(String routeName, {Object? arguments}) {
    if (modalRouteBuilder != null) {
      final route = modalRouteBuilder!<Object?>(
          RouteSettings(name: routeName, arguments: arguments));
      return _navigator.push<Object?>(route);
    } else {
      return _navigator.pushNamed<Object?>(routeName, arguments: arguments);
    }
  }

  @override
  Future<void> pop<T extends Object?>([T? result]) async {
    _navigator.pop(result);
  }

  @override
  Future<void> popUntil(String routeName) async {
    _navigator.popUntil((route) {
      return route.settings.name == routeName || route.isFirst;
    });
  }

  @override
  Future<Object?> pushAndRemoveUntil(String routeName,
      {Object? arguments, required String untilRoute}) async {
    return _navigator.pushNamedAndRemoveUntil<Object?>(
      routeName,
      ModalRoute.withName(untilRoute),
      arguments: arguments,
    );
  }

  @override
  bool canPop() {
    return _navigator.canPop();
  }
}

class EasyNative {
  EasyNative._();

  static const MethodChannel _routerChannel = MethodChannel(
    'easy_native/router',
  );

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static EasyNativeFlutterRouter? _flutterRouter;
  static int _nextRequestId = 0;
  static final Map<String, _PendingNativeRoute> _pendingNativeRoutes =
      <String, _PendingNativeRoute>{};

  static void init({
    EasyNativeFlutterRouter? flutterRouter,
    GlobalKey<NavigatorState>? key,
    EasyNativeModalRouteBuilder? modalRouteBuilder,
    EasyNativeLogProvider? logProvider,
    bool closeNativeFlowOnInit = true,
  }) {
    if (flutterRouter != null) {
      _flutterRouter = flutterRouter;
    } else {
      _flutterRouter = EasyNativeDefaultFlutterRouter(
        key ?? navigatorKey,
        modalRouteBuilder: modalRouteBuilder,
      );
    }

    if (key != null) {
      _externalNavigatorKey = key;
    }
    if (logProvider != null) {
      EasyNativeLogger.provider = logProvider;
    }

    // 自动初始化消息总线和事件总线，对外部业务屏蔽细节
    EasyNativeEventBus.initialize();
    EasyNativeMessenger.initialize();
    _routerChannel.setMethodCallHandler(_handleNativeRouteCallback);

    if (closeNativeFlowOnInit) {
      unawaited(_closeNativeFlowOnInit());
    }
  }

  static Future<void> _closeNativeFlowOnInit() async {
    try {
      final activeNative = await hasActiveNativeFlow();
      if (!activeNative) return;
      await _invokeNativeRoute('closeAll', <String, Object?>{'result': null});
      EasyNativeLogger.log(
        EasyNativeLogLevel.info,
        'closed active native flow during EasyNative.init',
      );
    } catch (error, stackTrace) {
      EasyNativeLogger.log(
        EasyNativeLogLevel.warning,
        'failed to close native flow during EasyNative.init',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static GlobalKey<NavigatorState>? _externalNavigatorKey;

  static GlobalKey<NavigatorState> get key =>
      _externalNavigatorKey ?? navigatorKey;

  static Future<T?> push<T extends Object?>(
    String routeName, {
    Object? arguments,
  }) async {
    final res = await _route(
      action: EasyNativeRouteAction.push,
      routeName: routeName,
      arguments: arguments,
    );
    return res as T?;
  }

  static Future<T?> replace<T extends Object?>(
    String routeName, {
    Object? arguments,
    Object? result,
  }) async {
    final res = await _route(
      action: EasyNativeRouteAction.replace,
      routeName: routeName,
      arguments: arguments,
      result: result,
    );
    return res as T?;
  }

  static Future<T?> present<T extends Object?>(
    String routeName, {
    Object? arguments,
  }) async {
    final res = await _route(
      action: EasyNativeRouteAction.present,
      routeName: routeName,
      arguments: arguments,
    );
    return res as T?;
  }

  static Future<T?> pushAndRemoveUntil<T extends Object?>(
    String routeName, {
    Object? arguments,
    required String untilRoute,
  }) async {
    final res = await _route(
      action: EasyNativeRouteAction.pushAndRemoveUntil,
      routeName: routeName,
      arguments: arguments,
      untilRoute: untilRoute,
    );
    return res as T?;
  }

  static Future<void> pop<T extends Object?>([
    T? result,
  ]) async {
    await _guarded(() async {
      final activeNative = await _hasActiveNativeFlowStrict();

      if (activeNative) {
        final formattedResult = _normalizeArguments(result);
        await _invokeNativeRoute('pop', <String, Object?>{
          'result': formattedResult,
        });
        return;
      }

      final router = _flutterRouter;
      if (router == null) {
        throw const EasyNativeRouteFailure(
            'Flutter router is not initialized.');
      }

      if (!router.canPop()) {
        EasyNativeLogger.log(
          EasyNativeLogLevel.warning,
          'Flutter navigator cannot pop',
        );
        return;
      }

      await router.pop<T>(result);
    });
  }

  static Future<void> popUntil(String routeName) async {
    await _route(action: EasyNativeRouteAction.popUntil, routeName: routeName);
  }

  static Future<void> closeAll<T extends Object?>([
    T? result,
  ]) async {
    await _guarded(() async {
      final formattedResult = _normalizeArguments(result);
      await _invokeNativeRoute('closeAll', <String, Object?>{
        'result': formattedResult,
      });
    });
  }

  static Future<Object?> _handleNativeRouteCallback(MethodCall call) async {
    switch (call.method) {
      case 'completeRoute':
        final args = call.arguments as Map<dynamic, dynamic>? ?? const {};
        final requestId = args['requestId'] as String?;
        if (requestId == null || requestId.isEmpty) {
          return false;
        }
        final pending = _pendingNativeRoutes.remove(requestId);
        if (pending == null) {
          EasyNativeLogger.log(
            EasyNativeLogLevel.warning,
            'native route completion ignored for unknown requestId=$requestId',
          );
          return false;
        }
        if (args['success'] == false) {
          pending.completer.completeError(
            EasyNativeRouteFailure(
              args['message'] as String? ?? 'Native route failed',
              action: args['action'] as String?,
            ),
          );
        } else {
          pending.completer.complete(_normalizePlatformValue(args['result']));
        }
        return true;
      default:
        throw MissingPluginException('Unknown router method ${call.method}');
    }
  }

  static Future<bool> canPop() async {
    if (await hasActiveNativeFlow()) {
      return true;
    }
    return _flutterRouter?.canPop() ?? false;
  }

  static Future<bool> isNativeRoute(String routeName) async {
    try {
      final result = await _routerChannel.invokeMethod<bool>(
        'isNativeRoute',
        <String, Object?>{'routeName': routeName},
      );
      return result ?? false;
    } catch (error, stackTrace) {
      EasyNativeLogger.log(
        EasyNativeLogLevel.warning,
        'isNativeRoute failed for $routeName',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  static Future<bool> hasActiveNativeFlow() async {
    try {
      final result = await _routerChannel.invokeMethod<bool>(
        'hasActiveNativeFlow',
      );
      return result ?? false;
    } catch (error, stackTrace) {
      EasyNativeLogger.log(
        EasyNativeLogLevel.warning,
        'hasActiveNativeFlow failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  static Future<bool> _isNativeRouteStrict(String routeName) async {
    final result = await _routerChannel.invokeMethod<bool>(
      'isNativeRoute',
      <String, Object?>{'routeName': routeName},
    );

    if (result == null) {
      throw const EasyNativeRouteFailure('isNativeRoute returned null');
    }

    return result;
  }

  static Future<bool> _hasActiveNativeFlowStrict() async {
    final result = await _routerChannel.invokeMethod<bool>(
      'hasActiveNativeFlow',
    );

    if (result == null) {
      throw const EasyNativeRouteFailure('hasActiveNativeFlow returned null');
    }

    return result;
  }

  static Future<Object?> _route({
    required EasyNativeRouteAction action,
    required String routeName,
    Object? arguments,
    Object? result,
    String? untilRoute,
  }) {
    return _guarded(() async {
      EasyNativeLogger.log(
        EasyNativeLogLevel.debug,
        'route action=${action.name} route=$routeName',
      );

      final formattedArguments = _normalizeArguments(arguments);
      final formattedResult = _normalizeArguments(result);

      final targetIsNative = await _isNativeRouteStrict(routeName);
      final activeNative = await _hasActiveNativeFlowStrict();

      if (targetIsNative) {
        final requestId =
            _shouldAwaitNativeRoute(action) ? _createRequestId() : null;
        final pendingNativeRoute =
            requestId == null ? null : _pendingNativeRoutes[requestId];

        if (action == EasyNativeRouteAction.popUntil && !activeNative) {
          throw EasyNativeRouteFailure(
            'Cannot popUntil native route without active native flow',
            action: action.name,
          );
        }

        try {
          final nativeResult =
              await _invokeNativeRoute(action.name, <String, Object?>{
            'routeName': routeName,
            'arguments': formattedArguments,
            'result': formattedResult,
            'untilRoute': untilRoute,
            'requestId': requestId,
          });
          if (!activeNative) {
            _syncFlutterStackAfterOpeningNative(
              action: action,
              result: formattedResult,
              untilRoute: untilRoute,
            );
          }
          if (requestId != null && pendingNativeRoute != null) {
            return await pendingNativeRoute.completer.future;
          }
          return nativeResult;
        } catch (e) {
          if (requestId != null) {
            _pendingNativeRoutes.remove(requestId);
          }
          rethrow;
        }
      }

      if (activeNative) {
        await _invokeNativeRoute(
          'closeAll',
          <String, Object?>{'result': formattedResult},
        );

        if (action == EasyNativeRouteAction.replace) {
          return _routeFlutter(
            action: EasyNativeRouteAction.push,
            routeName: routeName,
            arguments: formattedArguments,
            result: formattedResult,
            untilRoute: untilRoute,
          );
        }
      }

      return _routeFlutter(
        action: action,
        routeName: routeName,
        arguments: formattedArguments,
        result: formattedResult,
        untilRoute: untilRoute,
      );
    });
  }

  static bool _shouldAwaitNativeRoute(EasyNativeRouteAction action) {
    switch (action) {
      case EasyNativeRouteAction.push:
      case EasyNativeRouteAction.replace:
      case EasyNativeRouteAction.present:
      case EasyNativeRouteAction.pushAndRemoveUntil:
        return true;
      case EasyNativeRouteAction.pop:
      case EasyNativeRouteAction.popUntil:
        return false;
    }
  }

  static String _createRequestId() {
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${_nextRequestId++}';
    _pendingNativeRoutes[requestId] = _PendingNativeRoute(Completer<Object?>());
    return requestId;
  }

  static Future<Object?> _routeFlutter({
    required EasyNativeRouteAction action,
    required String routeName,
    Object? arguments,
    Object? result,
    String? untilRoute,
  }) async {
    final router = _flutterRouter;
    if (router == null) {
      throw const EasyNativeRouteFailure('Flutter router is not initialized.');
    }

    try {
      switch (action) {
        case EasyNativeRouteAction.push:
          return await router.push(routeName, arguments: arguments);
        case EasyNativeRouteAction.replace:
          return await router.replace(routeName,
              arguments: arguments, result: result);
        case EasyNativeRouteAction.present:
          return await router.present(routeName, arguments: arguments);
        case EasyNativeRouteAction.pop:
          if (!router.canPop()) {
            EasyNativeLogger.log(
              EasyNativeLogLevel.warning,
              'Flutter navigator cannot pop',
            );
            return null;
          }
          await router.pop(result);
          return null;
        case EasyNativeRouteAction.popUntil:
          await router.popUntil(routeName);
          return null;
        case EasyNativeRouteAction.pushAndRemoveUntil:
          if (untilRoute == null) {
            throw const EasyNativeRouteFailure(
                'untilRoute is required for pushAndRemoveUntil',
                action: 'pushAndRemoveUntil');
          }
          return await router.pushAndRemoveUntil(routeName,
              arguments: arguments, untilRoute: untilRoute);
      }
    } on EasyNativeRouteFailure {
      rethrow;
    } catch (error, stackTrace) {
      EasyNativeLogger.log(
        EasyNativeLogLevel.error,
        'Flutter routing failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw EasyNativeRouteFailure('Flutter routing error: $error');
    }
  }

  static void _syncFlutterStackAfterOpeningNative({
    required EasyNativeRouteAction action,
    Object? result,
    String? untilRoute,
  }) {
    final router = _flutterRouter;
    if (router == null) return;

    Future<void>? future;

    try {
      switch (action) {
        case EasyNativeRouteAction.replace:
          if (router.canPop()) {
            future = router.pop(result);
          }
          break;
        case EasyNativeRouteAction.pushAndRemoveUntil:
          if (untilRoute != null) {
            future = router.popUntil(untilRoute);
          }
          break;
        case EasyNativeRouteAction.push:
        case EasyNativeRouteAction.present:
        case EasyNativeRouteAction.pop:
        case EasyNativeRouteAction.popUntil:
          break;
      }
    } catch (error, stackTrace) {
      EasyNativeLogger.log(
        EasyNativeLogLevel.warning,
        'failed to sync Flutter stack after opening native',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }

    if (future != null) {
      unawaited(
        future.catchError((Object error, StackTrace stackTrace) {
          EasyNativeLogger.log(
            EasyNativeLogLevel.warning,
            'failed to sync Flutter stack after opening native',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    }
  }

  static Future<Object?> _invokeNativeRoute(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result = await _routerChannel.invokeMethod<Object?>(
        method,
        arguments,
      );
      return _parseNativeRouteResult(result);
    } catch (error, stackTrace) {
      EasyNativeLogger.log(
        EasyNativeLogLevel.error,
        'native route method failed: $method',
        error: error,
        stackTrace: stackTrace,
      );
      throw EasyNativeRouteFailure(error.toString(), action: method);
    }
  }

  static Future<T> _guarded<T>(
    Future<T> Function() run,
  ) async {
    try {
      return await run();
    } on EasyNativeRouteFailure {
      rethrow;
    } catch (error, stackTrace) {
      EasyNativeLogger.log(
        EasyNativeLogLevel.error,
        'route action failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw EasyNativeRouteFailure(error.toString());
    }
  }

  static Object? _parseNativeRouteResult(Object? value) {
    if (value is! Map) {
      return null;
    }
    final success = value['success'] as bool? ?? false;
    final action = value['action'] as String?;
    final message = value['message'] as String?;
    final data = value['data'];
    if (!success) {
      throw EasyNativeRouteFailure(message ?? 'Native route failed',
          action: action);
    }
    if (data is Map) {
      return data['result'];
    }
    return null;
  }

  static Object? _normalizeArguments(Object? value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    }

    if (value is EasyNativeSerializable) {
      final json = value.toJson();
      try {
        jsonEncode(json);
        return json;
      } catch (error) {
        throw EasyNativeRouteFailure(
          'EasyNativeSerializable.toJson() must return a JSON serializable map: $error',
        );
      }
    }

    if (value is Map || value is List) {
      try {
        jsonEncode(value);
        return value;
      } catch (error) {
        throw EasyNativeRouteFailure(
          'Cross-end arguments must be JSON serializable: $error',
        );
      }
    }

    throw EasyNativeRouteFailure(
      'Cross-end arguments must be JSON serializable. Current type: ${value.runtimeType}',
    );
  }

  static Object? _normalizePlatformValue(Object? value) {
    if (value is Map) {
      return value.map<String, Object?>(
        (key, item) => MapEntry(
          key.toString(),
          _normalizePlatformValue(item),
        ),
      );
    }
    if (value is List) {
      return value.map(_normalizePlatformValue).toList();
    }
    return value;
  }
}
