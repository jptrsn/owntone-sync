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

  String? _validateServerUrl(String? url) {
    if (url == null || url.isEmpty) {
      return 'Please enter a server URL';
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'URL must start with http:// or https://';
    }

    // Parse the URL to extract the host
    try {
      final uri = Uri.parse(url);
      final host = uri.host;

      // If using HTTP (not HTTPS), validate it's a private/local IP
      if (url.startsWith('http://') && !_isLocalAddress(host)) {
        return 'HTTP is only allowed for local network addresses.\n'
            'Use HTTPS for remote servers, or use a local IP like:\n'
            '• 192.168.x.x\n'
            '• 10.x.x.x\n'
            '• 172.16-31.x.x\n'
            '• localhost / 127.0.0.1';
      }

      return null;
    } catch (e) {
      return 'Invalid URL format';
    }
  }

  bool _isLocalAddress(String host) {
    // Check for localhost
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }

    // Check for private IP ranges
    try {
      final parts = host.split('.');
      if (parts.length != 4) return false;

      final octets = parts.map(int.parse).toList();

      // 10.0.0.0/8
      if (octets[0] == 10) return true;

      // 172.16.0.0/12
      if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;

      // 192.168.0.0/16
      if (octets[0] == 192 && octets[1] == 168) return true;

      // 169.254.0.0/16 (link-local)
      if (octets[0] == 169 && octets[1] == 254) return true;

      return false;
    } catch (e) {
      // Not a valid IPv4 address, might be hostname
      // For safety, reject HTTP for non-IP hostnames
      return false;
    }
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
                validator: _validateServerUrl,
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
                              content: Text(
                                'To track your playback statistics, OwnTone Sync needs notification access.\n\n'
                                'What data is collected:\n'
                                '• Song titles, artists, and album names from media notifications\n'
                                '• Play and skip events\n\n'
                                'Where it goes:\n'
                                '• Only to YOUR OwnTone server (${provider.serverUrl})\n'
                                '• Never sent to the developer or third parties\n\n'
                                'What we DON\'T collect:\n'
                                '• Other app notifications\n'
                                '• Messages, emails, or personal notifications\n\n'
                                'You can revoke this permission anytime in Settings.',
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
