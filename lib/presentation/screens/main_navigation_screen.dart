import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import 'sync_screen.dart';
import 'browse_screen.dart';
import 'history_screen.dart';
import 'server_config_screen.dart';
import '../widgets/mini_player.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    SyncScreen(),
    BrowseScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('OwnTone Sync'),
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            actions: [
              Consumer<SyncProvider>(
                builder: (context, provider, child) {
                  if (provider.isConfigured) {
                    return IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ServerConfigScreen(),
                          ),
                        );
                      },
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          body: _screens[_currentIndex],
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 56,
          child: MiniPlayer(),
        ),
        Scaffold(
          body: Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.sync), label: 'Sync'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.library_music),
                  label: 'Browse',
                ),
                BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
