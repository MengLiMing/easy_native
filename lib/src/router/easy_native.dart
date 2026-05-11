import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:result_dart/result_dart.dart';

abstract class EasyNativeSerializable {
  Map<String, dynamic> toJson();
}

enum EasyNativeLogLevel { debug, info, warning, error }

typedef EasyNativeLogProvider =
    void Function(
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

class EasyNativeRouteSuccess {
  const EasyNativeRouteSuccess({this.message, this.action, this.data});

  final String? message;
  final String? action;
  final Map<String, dynamic>? data;
}

typedef EasyNativeRouteResult =
    ResultDart<EasyNativeRouteSuccess, EasyNativeRouteFailure>;

typedef EasyNativeModalRouteBuilder =
    Route<T> Function<T>(RouteSettings settings);

class EasyNative {
  EasyNative._();

  static const MethodChannel _routerChannel = MethodChannel(
    'easy_native/router',
  );

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static EasyNativeModalRouteBuilder? _modalRouteBuilder;
  static bool _isRouting = false;

  static void init({
    GlobalKey<NavigatorState>? key,
    EasyNativeModalRouteBuilder? modalRouteBuilder,
    EasyNativeLogProvider? logProvider,
    bool closeNativeFlowOnInit = true,
  }) {
    if (key != null) {
      _externalNavigatorKey = key;
    }
    if (modalRouteBuilder != null) {
      _modalRouteBuilder = modalRouteBuilder;
    }
    if (logProvider != null) {
      EasyNativeLogger.provider = logProvider;
    }
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

  static NavigatorState get _navigator {
    final state = key.currentState;
    assert(state != null, 'EasyNative 尚未挂载到 MaterialApp.navigatorKey。');
    return state!;
  }

  static Future<EasyNativeRouteResult> push(
    String routeName, {
    Object? arguments,
  }) {
    return _route(
      action: EasyNativeRouteAction.push,
      routeName: routeName,
      arguments: arguments,
    );
  }

  static Future<EasyNativeRouteResult> replace(
    String routeName, {
    Object? arguments,
    Object? result,
  }) {
    return _route(
      action: EasyNativeRouteAction.replace,
      routeName: routeName,
      arguments: arguments,
      result: result,
    );
  }

  static Future<EasyNativeRouteResult> present(
    String routeName, {
    Object? arguments,
  }) {
    return _route(
      action: EasyNativeRouteAction.present,
      routeName: routeName,
      arguments: arguments,
    );
  }

  static Future<EasyNativeRouteResult> pushAndRemoveUntil(
    String routeName, {
    Object? arguments,
    required String untilRoute,
  }) {
    return _route(
      action: EasyNativeRouteAction.pushAndRemoveUntil,
      routeName: routeName,
      arguments: arguments,
      untilRoute: untilRoute,
    );
  }

  static Future<EasyNativeRouteResult> pop<T extends Object?>([
    T? result,
  ]) async {
    return _guarded(() async {
      final activeNative = await _hasActiveNativeFlowStrict();

      if (activeNative) {
        final formattedResult = _normalizeArguments(result);
        return _invokeNativeRoute('pop', <String, Object?>{
          'result': formattedResult,
        });
      }

      if (!_navigator.canPop()) {
        return _routeFailure('Flutter navigator cannot pop');
      }

      _navigator.pop<T>(result);
      return _routeSuccess(action: 'flutterPop');
    });
  }

  static Future<EasyNativeRouteResult> popUntil(String routeName) async {
    return _route(action: EasyNativeRouteAction.popUntil, routeName: routeName);
  }

  static Future<EasyNativeRouteResult> closeAll<T extends Object?>([
    T? result,
  ]) {
    return _guarded(() async {
      final formattedResult = _normalizeArguments(result);
      return _invokeNativeRoute('closeAll', <String, Object?>{
        'result': formattedResult,
      });
    });
  }

  static Future<bool> canPop() async {
    if (await hasActiveNativeFlow()) {
      return true;
    }
    return _navigator.canPop();
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

  static Future<EasyNativeRouteResult> _route({
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
        if (action == EasyNativeRouteAction.popUntil && !activeNative) {
          return _routeFailure(
            'Cannot popUntil native route without active native flow',
            action: action.name,
          );
        }

        final nativeResult =
            await _invokeNativeRoute(action.name, <String, Object?>{
              'routeName': routeName,
              'arguments': formattedArguments,
              'result': formattedResult,
              'untilRoute': untilRoute,
            });
        if (nativeResult.isError()) {
          return nativeResult;
        }
        if (!activeNative) {
          _syncFlutterStackAfterOpeningNative(
            action: action,
            result: formattedResult,
            untilRoute: untilRoute,
          );
        }
        return nativeResult;
      }

      if (activeNative) {
        final closeResult = await _invokeNativeRoute(
          'closeAll',
          <String, Object?>{'result': formattedResult},
        );

        final closeFailed = closeResult.fold((_) => false, (_) => true);

        if (closeFailed) {
          return closeResult;
        }

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

  static Future<EasyNativeRouteResult> _routeFlutter({
    required EasyNativeRouteAction action,
    required String routeName,
    Object? arguments,
    Object? result,
    String? untilRoute,
  }) async {
    switch (action) {
      case EasyNativeRouteAction.push:
        unawaited(
          _navigator.pushNamed<Object?>(routeName, arguments: arguments),
        );
        return _routeSuccess(action: 'flutterPush');
      case EasyNativeRouteAction.replace:
        unawaited(
          _navigator.pushReplacementNamed<Object?, Object?>(
            routeName,
            arguments: arguments,
            result: result,
          ),
        );
        return _routeSuccess(action: 'flutterReplace');
      case EasyNativeRouteAction.present:
        final settings = RouteSettings(name: routeName, arguments: arguments);
        final route = _modalRouteBuilder?.call<Object?>(settings);
        if (route != null) {
          unawaited(_navigator.push<Object?>(route));
        } else {
          unawaited(
            _navigator.pushNamed<Object?>(routeName, arguments: arguments),
          );
        }
        return _routeSuccess(action: 'flutterPresent');
      case EasyNativeRouteAction.pop:
        if (!_navigator.canPop()) {
          return _routeFailure('Flutter navigator cannot pop');
        }
        _navigator.pop(result);
        return _routeSuccess(action: 'flutterPop');
      case EasyNativeRouteAction.popUntil:
        var found = false;
        _navigator.popUntil((route) {
          if (route.settings.name == routeName) {
            found = true;
            return true;
          }
          return route.isFirst;
        });
        if (!found) {
          return _routeFailure(
            'Flutter route not found: $routeName',
            action: 'flutterPopUntil',
          );
        }
        return _routeSuccess(action: 'flutterPopUntil');
      case EasyNativeRouteAction.pushAndRemoveUntil:
        unawaited(
          _navigator.pushNamedAndRemoveUntil<Object?>(
            routeName,
            ModalRoute.withName(untilRoute ?? '/'),
            arguments: arguments,
          ),
        );
        return _routeSuccess(action: 'flutterPushAndRemoveUntil');
    }
  }

  static void _syncFlutterStackAfterOpeningNative({
    required EasyNativeRouteAction action,
    Object? result,
    String? untilRoute,
  }) {
    try {
      switch (action) {
        case EasyNativeRouteAction.replace:
          if (_navigator.canPop()) {
            _navigator.pop(result);
          }
          break;
        case EasyNativeRouteAction.pushAndRemoveUntil:
          _navigator.popUntil(ModalRoute.withName(untilRoute ?? '/'));
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
    }
  }

  static Future<EasyNativeRouteResult> _invokeNativeRoute(
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
      return _routeFailure(error.toString(), action: method);
    }
  }

  static Future<EasyNativeRouteResult> _guarded(
    Future<EasyNativeRouteResult> Function() run,
  ) async {
    if (_isRouting) {
      return _routeFailure('A routing action is already running');
    }
    _isRouting = true;
    try {
      return await run();
    } on EasyNativeRouteFailure catch (error) {
      return _routeFailure(error.message, action: error.action);
    } catch (error, stackTrace) {
      EasyNativeLogger.log(
        EasyNativeLogLevel.error,
        'route action failed',
        error: error,
        stackTrace: stackTrace,
      );
      return _routeFailure(error.toString());
    } finally {
      _isRouting = false;
    }
  }

  static EasyNativeRouteResult _routeSuccess({
    String? action,
    Map<String, dynamic>? data,
    String? message,
  }) {
    return Success<EasyNativeRouteSuccess, EasyNativeRouteFailure>(
      EasyNativeRouteSuccess(action: action, data: data, message: message),
    );
  }

  static EasyNativeRouteResult _routeFailure(String message, {String? action}) {
    return Failure<EasyNativeRouteSuccess, EasyNativeRouteFailure>(
      EasyNativeRouteFailure(message, action: action),
    );
  }

  static EasyNativeRouteResult _parseNativeRouteResult(Object? value) {
    if (value is! Map) {
      return _routeSuccess();
    }
    final success = value['success'] as bool? ?? false;
    final action = value['action'] as String?;
    final message = value['message'] as String?;
    final data = value['data'];
    if (!success) {
      return _routeFailure(message ?? 'Native route failed', action: action);
    }
    return _routeSuccess(
      action: action,
      message: message,
      data: data is Map ? Map<String, dynamic>.from(data) : null,
    );
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
}
