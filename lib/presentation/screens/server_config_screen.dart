import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final provider = context.read<SyncProvider>();
    _urlController = TextEditingController(
      text: provider.serverUrl.isNotEmpty
          ? provider.serverUrl
          : 'http://192.168.1.100:3689',
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Configuration'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.dns, size: 64),
              const SizedBox(height: 24),
              const Text(
                'OwnTone Server',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your OwnTone server URL',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'http://192.168.1.100:3689',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a server URL';
                  }
                  if (!value.startsWith('http://') &&
                      !value.startsWith('https://')) {
                    return 'URL must start with http:// or https://';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              Consumer<SyncProvider>(
                builder: (context, provider, child) {
                  return SwitchListTile(
                    title: const Text('Track Playback Events'),
                    subtitle: const Text(
                      'Send play/skip data to your OwnTone server',
                    ),
                    value: provider.eventTrackingEnabled,
                    onChanged: (value) async {
                      if (value) {
                        // Check if permission is granted
                        final hasPermission = await provider
                            .checkEventTrackingPermission();
                        if (!hasPermission && context.mounted) {
                          // Show dialog explaining the permission
                          final shouldRequest = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Notification Access Required'),
                              content: const Text(
                                'To track your playback statistics, OwnTone Sync needs notification access.\n\n'
                                'Why? Android requires "notification listener" permission to detect when songs play or skip in other music apps. '
                                'This is the same permission used by apps like Last.fm scrobbler.\n\n'
                                'Privacy: OwnTone Sync only reads media notifications (song titles, artists). '
                                'Your data is ONLY sent to your personal OwnTone server, never to any third party.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Grant Access'),
                                ),
                              ],
                            ),
                          );

                          if (shouldRequest == true) {
                            await provider.requestEventTrackingPermission();
                            // Wait a bit then check again
                            await Future.delayed(const Duration(seconds: 1));
                            final granted = await provider
                                .checkEventTrackingPermission();
                            if (granted) {
                              await provider.setEventTracking(true);
                            }
                          }
                        } else {
                          await provider.setEventTracking(true);
                        }
                      } else {
                        await provider.setEventTracking(false);
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final provider = context.read<SyncProvider>();
                    final navigator = Navigator.of(context);
                    await provider.setServerUrl(_urlController.text.trim());
                    navigator.pop();
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Save', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
