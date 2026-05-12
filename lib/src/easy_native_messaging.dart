part of easy_native;

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
      EasyNativeEvent(
        type: type,
        data: _normalizeMessageValue(data),
      ).toJson(),
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
      final rawName = args['method'] as String?;
      final name = rawName?.trim();

      if (name == null || name.isEmpty) {
        throw MissingPluginException(
            'Flutter method is not registered: $rawName');
      }

      final handler = _flutterHandlers[name];
      if (handler == null) {
        throw MissingPluginException('Flutter method is not registered: $name');
      }
      final result = await handler(args['data']);
      return _normalizeMessageValue(result);
    });
  }

  static void registerFlutterMethod(
    String method,
    EasyNativeMethodHandler handler,
  ) {
    final methodName = method.trim();
    if (methodName.isEmpty) {
      throw ArgumentError.value(method, 'method', 'method cannot be empty');
    }
    _flutterHandlers[methodName] = handler;
  }

  static void unregisterFlutterMethod(String method) {
    _flutterHandlers.remove(method.trim());
  }

  static Future<T?> invokeNative<T>(String method, {Object? data}) async {
    final methodName = method.trim();
    if (methodName.isEmpty) {
      throw ArgumentError.value(method, 'method', 'method cannot be empty');
    }

    EasyNativeLogger.log(
      EasyNativeLogLevel.debug,
      'invoke native method=$methodName',
    );
    final formattedData = _normalizeMessageValue(data);

    final result = await _methodChannel.invokeMethod<T>(
      'invokeNative',
      <String, Object?>{
        'method': methodName,
        'data': formattedData,
      },
    );
    return result;
  }
}

Object? _normalizeMessageValue(Object? value) {
  if (value == null || value is num || value is String || value is bool) {
    return value;
  }

  if (value is EasyNativeSerializable) {
    final json = value.toJson();
    try {
      jsonEncode(json);
      return json;
    } catch (error) {
      throw PlatformException(
        code: 'invalid_message_value',
        message:
            'EasyNativeSerializable.toJson() must return a JSON serializable map: $error',
      );
    }
  }

  if (value is Map || value is List) {
    try {
      jsonEncode(value);
      return value;
    } catch (error) {
      throw PlatformException(
        code: 'invalid_message_value',
        message: 'Messenger value must be JSON serializable: $error',
      );
    }
  }

  throw PlatformException(
    code: 'invalid_message_value',
    message:
        'Messenger value must be JSON serializable. Current type: ${value.runtimeType}',
  );
}
