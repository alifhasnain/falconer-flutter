import 'package:flutter/material.dart';
import 'package:falconer/falconer.dart';

import 'api_clients.dart' as api;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Falconer captures only in DEBUG by default. To capture in a RELEASE build,
  // opt in EXPLICITLY (this persists HTTP data on-device — see README):
  //
  // await Falconer.configure(const FalconerConfig(
  //   enabled: true,
  //   enableInReleaseBuilds: true,
  // ));
  //
  // Default demo config: debug capture with strong header redaction plus a
  // custom secret header, kept for one day.
  await Falconer.configure(
    FalconerConfig(
      redactHeaders: {...FalconerConfig.defaultRedactHeaders, 'X-Demo-Secret'},
      retention: RetentionPeriod.oneDay,
    ),
  );

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Falconer demo',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3457D5),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _run(
    BuildContext context,
    String label,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text('$label — captured')));
    } catch (_) {
      // Errors (404, timeouts) are still captured; the failure is expected.
      messenger.showSnackBar(
        SnackBar(content: Text('$label — captured (request failed)')),
      );
    }
  }

  Future<void> _enableNotifications(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await Falconer.requestNotificationPermission();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          granted ? 'Notifications enabled' : 'Notifications denied',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Falconer demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _CountBanner(),
          const SizedBox(height: 8),
          const Text(
            'Captured traffic appears in the Falconer notification — tap it, or '
            '"Open inspector" below, to inspect. Two Dio clients share one list.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Make requests',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => _run(context, 'JSON GET', api.jsonGet),
                child: const Text('JSON GET'),
              ),
              FilledButton.tonal(
                onPressed: () => _run(context, 'Form POST', api.formPost),
                child: const Text('Form POST'),
              ),
              FilledButton.tonal(
                onPressed: () => _run(context, 'Image GET', api.imageGet),
                child: const Text('Image GET'),
              ),
              FilledButton.tonal(
                onPressed: () => _run(context, '404', api.notFound),
                child: const Text('404 error'),
              ),
              FilledButton.tonal(
                onPressed: () => _run(context, 'Slow 3s', api.slowRequest),
                child: const Text('Slow 3s'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Inspector',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: Falconer.launchUi,
                child: const Text('Open inspector'),
              ),
              OutlinedButton(
                onPressed: () => _enableNotifications(context),
                child: const Text('Enable notifications'),
              ),
              OutlinedButton(
                onPressed: Falconer.clear,
                child: const Text('Clear all'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live transaction count via the EventChannel.
class _CountBanner extends StatelessWidget {
  const _CountBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Falconer.transactionCount,
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '$count captured',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        );
      },
    );
  }
}
