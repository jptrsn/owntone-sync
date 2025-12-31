import 'package:flutter/material.dart';
import 'package:owntone_sync/data/models/sync_state.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'presentation/providers/sync_provider.dart';
import 'presentation/screens/main_navigation_screen.dart';
import 'data/models/sync_schedule.dart';
import 'data/repositories/owntone_api_repository.dart';
import 'data/repositories/local_database_repository.dart';
import 'data/repositories/file_system_repository.dart';
import 'domain/services/sync_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('[Background] Starting background sync task');

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
        print('[Background] No server URL configured');
        return Future.value(false);
      }

      if (scheduleJson == null) {
        print('[Background] No schedule configured');
        return Future.value(false);
      }

      if (selectedPlaylistIdsJson == null || selectedPlaylistIdsJson.isEmpty) {
        print('[Background] No playlists selected');
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
        print(
          '[Background] Not time to sync. Current: ${now.hour}:${now.minute}, Scheduled: ${schedule.hour}:${schedule.minute}',
        );
        if (syncState.isRunning) {
          print('[Background] Sync already in progress');
        }
        if (syncState.lastSyncTime != null) {
          print('[Background] Last sync: ${syncState.lastSyncTime}');
        }
        return Future.value(true);
      }

      print(
        '[Background] Time to sync! Starting sync of ${selectedPlaylistIds.length} playlists',
      );

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
        final result = await syncService.syncPlaylists(selectedPlaylistIds);

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
          print(
            '[Background] Sync completed successfully. Downloaded: ${result.tracksDownloaded}, Deleted: ${result.tracksDeleted}',
          );
          // TODO: Save to sync history database
          return Future.value(true);
        } else {
          print('[Background] Sync failed: ${result.error}');
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
    } catch (e, stackTrace) {
      print('[Background] Error during background sync: $e');
      print('[Background] Stack trace: $stackTrace');
      return Future.value(false);
    }
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().initialize(callbackDispatcher, isInDebugMode: true);

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
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const MainNavigationScreen(),
      ),
    );
  }
}
