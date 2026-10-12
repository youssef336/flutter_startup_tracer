import 'package:flutter/material.dart';
import 'package:flutter_startup_tracer/flutter_startup_tracer.dart';

import 'slow_work.dart';

/// The first real screen: loads its data, then marks the app interactive.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await fakeIo(250); // The feed the user came for.
    if (!mounted) {
      return;
    }
    setState(() => _loaded = true);
    StartupTracer.of(context).markInteractive('home');
  }

  @override
  Widget build(BuildContext context) {
    final StartupTracer? trace = StartupTracer.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Startup tracer')),
      body: !_loaded || trace == null
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<StartupReport?>(
              valueListenable: trace.completed,
              builder: (BuildContext context, StartupReport? report, Widget? _) {
                if (report == null) {
                  return const Center(child: Text('Waiting for deferred work...'));
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: Text(
                      report.toPrettyString(barWidth: 30),
                      key: const Key('report'),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
