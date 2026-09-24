import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              'OwnTone Sync',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const Center(child: Text('Version 0.1.8')),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'A music player for your OwnTone server. '
              'Syncs playlists to the device, plays them offline, '
              'and sends play and skip counts back to the server.',
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
