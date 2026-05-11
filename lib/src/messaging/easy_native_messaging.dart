import 'dart:async';

import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

import '../router/easy_native.dart';

typedef EasyNativeMethodHandler = FutureOr<Object?> Function(Object? data);

class EasyNativeEvent {
  const EasyNativeEvent({required this.type, this.data});

  final String type;
  final Object? data;

  factory EasyNativeEvent.fromJson(Map<dynamic, dynamic> json) {
    return EasyNativeEvent(
      type: json['type'] as String? ?? '',
      data: json['data'],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'data': data,
  };
}

class EasyNativeEventBus {
  EasyNativeEventBus._();

  static const MethodChannel _eventChannel = MethodChannel(
    'easy_native/event_bus',
  );

  static final PublishSubject<EasyNativeEvent> _nativeEvents =
      PublishSubject<EasyNativeEvent>();
  static bool _initialized = false;

  static Stream<EasyNativeEvent> get nativeEvents => _nativeEvents.stream;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _eventChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'emitToFlutter') {
        throw MissingPluginException('Unknown event method ${call.method}');
      }
      final args = call.arguments as Map<dynamic, dynamic>? ?? const {};
      EasyNativeLogger.log(
        EasyNativeLogLevel.debug,
        'event from native type=${args['type'] ?? ''}',
      );
      _nativeEvents.add(EasyNativeEvent.fromJson(args));
      return true;
    });
  }

  static Future<void> emitToNative(String type, {Object? data}) async {
    EasyNativeLogger.log(
      EasyNativeLogLevel.debug,
      'event to native type=$type',
    );
    await _eventChannel.invokeMethod<void>(
      'emitToNative',
      EasyNativeEvent(type: type, data: data).toJson(),
    );
  }
}

class EasyNativeMessenger {
  EasyNativeMessenger._();

  static const MethodChannel _methodChannel = MethodChannel(
    'easy_native/methods',
  );

  static final Map<String, EasyNativeMethodHandler> _flutterHandlers =
      <String, EasyNativeMethodHandler>{};
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _methodChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'invokeFlutter') {
        throw MissingPluginException('Unknown method ${call.method}');
      }
      final args = call.arguments as Map<dynamic, dynamic>? ?? const {};
      final name = args['method'] as String?;
      final handler = name == null ? null : _flutterHandlers[name];
      if (handler == null) {
        throw MissingPluginException('Flutter method is not registered: $name');
      }
      return handler(args['data']);
    });
  }

  static void registerFlutterMethod(
    String method,
    EasyNativeMethodHandler handler,
  ) {
    if (method.trim().isEmpty) {
      throw ArgumentError.value(method, 'method', 'method cannot be empty');
    }
    _flutterHandlers[method] = handler;
  }

  static void unregisterFlutterMethod(String method) {
    _flutterHandlers.remove(method);
  }

  static Future<T?> invokeNative<T>(String method, {Object? data}) async {
    EasyNativeLogger.log(
      EasyNativeLogLevel.debug,
      'invoke native method=$method',
    );
    final result = await _methodChannel.invokeMethod<T>(
      'invokeNative',
      <String, Object?>{'method': method, 'data': data},
    );
    return result;
  }
}
