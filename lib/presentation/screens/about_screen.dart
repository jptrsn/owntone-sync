import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../widgets/player_scaffold.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  /// The version comes from the package: the pubspec `version` becomes the
  /// Android versionName via the Flutter Gradle plugin, and the
  /// `getAppVersion` channel returns it. Never a literal — the hard-coded
  /// "Version 0.1.8" was still showing while the app was 0.2.0+18
  /// (ux-refactor §3 G9, U4 build item 3). If the channel fails the line
  /// simply stays absent: it is a cosmetic surface, not a fault.
  Future<void> _loadVersion() async {
    try {
      const channel = MethodChannel('dev.educoder.owntone_sync/sync');
      final version = await channel.invokeMethod<String>('getAppVersion');
      if (mounted && version != null) {
        setState(() => _version = version);
      }
    } catch (e) {
      debugPrint('[AboutScreen] getAppVersion failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // PlayerScaffold: the mini player survives navigating here (Phase U2
    // build item 1); zero-height at idle.
    return PlayerScaffold(
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          Center(
            child: Icon(
              Icons.library_music,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Owntone Player',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          if (_version != null) Center(child: Text('Version $_version')),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Your OwnTone library on your phone - '
              'synced home, played anywhere.',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Consumer<SyncProvider>(
            builder: (context, provider, _) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('Server'),
                  subtitle: Text(
                    provider.serverUrl.isEmpty
                        ? 'Not configured'
                        : provider.serverUrl,
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
