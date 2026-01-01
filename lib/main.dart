import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'data/models/sync_schedule.dart';
import 'data/models/sync_state.dart';
import 'data/repositories/file_system_repository.dart';
import 'data/repositories/local_database_repository.dart';
import 'data/repositories/owntone_api_repository.dart';
import 'domain/services/sync_service.dart';
import 'presentation/providers/sync_provider.dart';
import 'presentation/screens/main_navigation_screen.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Load configuration from SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      final serverUrl = prefs.getString('server_url');
      final scheduleJson = prefs.getString('sync_schedule');
      final selectedPlaylistIdsJson = prefs.getStringList(
        'selected_playlist_ids',
      );
      final deleteOrphanedFiles =
          prefs.getBool('delete_orphaned_files') ?? false;
      final syncStateJson = prefs.getString('sync_state');

      if (serverUrl == null || serverUrl.isEmpty) {
        return Future.value(false);
      }

      if (scheduleJson == null) {
        return Future.value(false);
      }

      if (selectedPlaylistIdsJson == null || selectedPlaylistIdsJson.isEmpty) {
        return Future.value(false);
      }

      final schedule = SyncSchedule.fromJson(json.decode(scheduleJson));
      final selectedPlaylistIds = selectedPlaylistIdsJson
          .map((id) => int.parse(id))
          .toList();
      final syncState = syncStateJson != null
          ? SyncState.fromJson(json.decode(syncStateJson))
          : SyncState();

      // Check if we should sync now
      final now = DateTime.now();
      if (!schedule.shouldSyncNow(now, syncState)) {
        return Future.value(true);
      }

      // Mark sync as running
      final runningSyncState = SyncState(
        isRunning: true,
        lastSyncTime: syncState.lastSyncTime,
        lastSyncSuccess: syncState.lastSyncSuccess,
      );
      await prefs.setString(
        'sync_state',
        json.encode(runningSyncState.toJson()),
      );

      try {
        // Initialize services
        final apiRepo = OwnToneApiRepository(baseUrl: serverUrl);
        final dbRepo = LocalDatabaseRepository();
        final fileRepo = FileSystemRepository();

        final syncService = SyncService(
          apiRepo: apiRepo,
          dbRepo: dbRepo,
          fileRepo: fileRepo,
        );

        syncService.deleteOrphanedFiles = deleteOrphanedFiles;

        // Run the sync
        final result = await syncService.syncPlaylists(
          selectedPlaylistIds,
          triggerType: 'scheduled',
        );

        // Update sync state
        final completedSyncState = SyncState(
          isRunning: false,
          lastSyncTime: DateTime.now(),
          lastSyncSuccess: result.success,
        );
        await prefs.setString(
          'sync_state',
          json.encode(completedSyncState.toJson()),
        );

        if (result.success) {
          return Future.value(true);
        } else {
          return Future.value(false);
        }
      } catch (e) {
        // Mark sync as no longer running on error
        final errorSyncState = SyncState(
          isRunning: false,
          lastSyncTime: syncState.lastSyncTime,
          lastSyncSuccess: false,
        );
        await prefs.setString(
          'sync_state',
          json.encode(errorSyncState.toJson()),
        );
        rethrow;
      }
    } catch (e) {
      return Future.value(false);
    }
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().initialize(callbackDispatcher);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SyncProvider(),
      child: MaterialApp(
        title: 'OwnTone Sync',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF37474F),
            brightness: Brightness.light,
            primary: const Color(0xFF37474F),
            secondary: const Color(0xFFF4511E),
            surface: Colors.white,
            onSurface: const Color(0xFF37474F),
          ),
          appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          chipTheme: ChipThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF37474F),
            brightness: Brightness.dark,
            primary: const Color(0xFFB0BEC5),
            secondary: const Color(0xFFFF7043),
            surface: const Color(0xFF121212),
            onSurface: const Color(0xFFE0E0E0),
          ),
          appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          chipTheme: ChipThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        themeMode: ThemeMode.system, // Respects system preference
        home: const MainNavigationScreen(),
      ),
    );
  }
}
