import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';

/// Storage / music folder status and grant.
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: Consumer<SyncProvider>(
        builder: (context, provider, _) {
          final granted = provider.hasStoragePermission;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    granted ? Icons.folder : Icons.folder_off,
                    size: 32,
                  ),
                  title: const Text('Music folder'),
                  subtitle: Text(
                    granted ? 'Folder access granted' : 'No folder access',
                  ),
                  isThreeLine: true,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: Text(granted ? 'Change folder' : 'Grant access'),
                onPressed: () async {
                  final ok = await provider.requestStoragePermission();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Folder access granted'
                              : 'Folder access not granted',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
