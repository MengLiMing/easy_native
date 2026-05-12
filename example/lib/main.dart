import 'dart:async';

import 'package:easy_native/easy_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  EasyNative.init(modalRouteBuilder: _modalRouteBuilder);
  runApp(const MyApp());
}

Route<T> _modalRouteBuilder<T>(RouteSettings settings) {
  return CupertinoPageRoute<T>(
    settings: settings,
    fullscreenDialog: true,
    builder: (context) =>
        _buildFlutterPage(settings.name ?? '/', settings.arguments),
  );
}

Widget _buildFlutterPage(
  String routeName,
  Object? arguments, [
  _MyAppState? appState,
]) {
  switch (routeName) {
    case '/flutter/list':
      return DemoFlutterPage(routeName: routeName, color: Colors.indigo);
    case '/flutter/profile':
      return DemoFlutterPage(routeName: routeName, color: Colors.teal);
    case '/flutter/modal':
      return DemoFlutterPage(routeName: routeName, color: Colors.deepOrange);
    default:
      return HomePage(
        logs: appState?._logs ?? const <String>[],
        onRun: appState?._run ?? _discardRun,
        onLog: appState?._log ?? (_) {},
      );
  }
}

Future<void> _discardRun(
  String label,
  Future<dynamic> Function() action,
) async {
  await action();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StreamSubscription<EasyNativeEvent> _subscription;
  final List<String> _logs = <String>[];

  @override
  void initState() {
    super.initState();
    _subscription = EasyNativeEventBus.nativeEvents.listen((event) async {
      _log('event from native: ${event.type}');
      if (event.type == 'replaceNativeC') {
        await EasyNative.replace(
          '/native/c',
          arguments: {'from': 'native_event'},
        );
      }
      if (event.type == 'replaceFlutterProfile') {
        await EasyNative.replace(
          '/flutter/profile',
          arguments: {'from': 'native_event'},
        );
      }
      if (event.type == 'pushFlutterProfile') {
        await EasyNative.push(
          '/flutter/profile',
          arguments: {'from': 'native_event'},
        );
      }
      if (event.type == 'popUntilFlutterHome') {
        await EasyNative.popUntil('/');
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _logs.insert(0, message);
    });
  }

  Future<void> _run(
    String label,
    Future<dynamic> Function() action,
  ) async {
    try {
      final result = await action();
      _log('$label -> success (result: $result)');
    } catch (e) {
      _log('$label -> failure ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: EasyNative.key,
      title: 'EasyNative Router Demo',
      onGenerateRoute: (settings) {
        return CupertinoPageRoute<void>(
          settings: settings,
          builder: (context) =>
              _buildFlutterPage(settings.name ?? '/', settings.arguments, this),
        );
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.logs,
    required this.onRun,
    required this.onLog,
    super.key,
  });

  final List<String> logs;
  final Future<void> Function(
    String label,
    Future<dynamic> Function() action,
  ) onRun;
  final void Function(String message) onLog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EasyNative unified router')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Button(
            label: 'push Flutter /flutter/list',
            onPressed: () =>
                onRun('push flutter', () => EasyNative.push('/flutter/list')),
          ),
          _Button(
            label: 'present Flutter /flutter/modal',
            onPressed: () => onRun(
              'present flutter',
              () => EasyNative.present('/flutter/modal'),
            ),
          ),
          _Button(
            label: 'push Native /native/a',
            onPressed: () => onRun(
              'push native',
              () => EasyNative.push('/native/a', arguments: {'from': 'home'}),
            ),
          ),
          _Button(
            label: 'push Native /native/a and await any result',
            onPressed: () => onRun(
              'push native await any result',
              () => EasyNative.push<Object?>(
                '/native/a',
                arguments: {'from': 'home_await_result'},
              ),
            ),
          ),
          _Button(
            label: 'replace Native /native/c',
            onPressed: () => onRun(
              'replace native',
              () => EasyNative.replace(
                '/native/c',
                arguments: {'from': 'home_replace'},
              ),
            ),
          ),
          _Button(
            label: 'present Native /native/a',
            onPressed: () =>
                onRun('present native', () => EasyNative.present('/native/a')),
          ),
          _Button(
            label: 'replace Flutter /flutter/profile',
            onPressed: () => onRun(
              'replace flutter',
              () => EasyNative.replace('/flutter/profile'),
            ),
          ),
          _Button(
            label: 'closeAll Native',
            onPressed: () => onRun('closeAll native', EasyNative.closeAll),
          ),
          const SizedBox(height: 16),
          const Text(
            'Native event cases: open /native/a, then use native buttons.',
          ),
          const SizedBox(height: 16),
          for (final log in logs.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(log),
            ),
        ],
      ),
    );
  }
}

class DemoFlutterPage extends StatelessWidget {
  const DemoFlutterPage({
    required this.routeName,
    required this.color,
    super.key,
  });

  final String routeName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(routeName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 96,
            alignment: Alignment.center,
            color: color.withValues(alpha: 0.15),
            child: Text(routeName, style: const TextStyle(fontSize: 22)),
          ),
          _Button(
            label: 'push Native /native/a',
            onPressed: () => EasyNative.push('/native/a'),
          ),
          _Button(
            label: 'pop with result',
            onPressed: () => EasyNative.pop(
              'result from Flutter $routeName',
            ),
          ),
          _Button(
            label: 'replace Native /native/c',
            onPressed: () => EasyNative.replace('/native/c'),
          ),
          _Button(
            label: 'pushAndRemoveUntil Flutter profile until /',
            onPressed: () => EasyNative.pushAndRemoveUntil(
              '/flutter/profile',
              untilRoute: '/',
            ),
          ),
          _Button(
            label: 'pushAndRemoveUntil Native c until /',
            onPressed: () => EasyNative.pushAndRemoveUntil(
              '/native/c',
              arguments: {'from': 'flutter_page_remove_until'},
              untilRoute: '/',
            ),
          ),
          _Button(label: 'pop', onPressed: () => EasyNative.pop()),
          _Button(
            label: 'popUntil /',
            onPressed: () => EasyNative.popUntil('/'),
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onPressed});

  final String label;
  final FutureOr<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: FilledButton(
        onPressed: () => unawaited(Future<void>.value(onPressed())),
        child: Text(label),
      ),
    );
  }
}
