import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';

import 'data/repositories/local_database_repository.dart';
import 'presentation/controllers/playback_controller.dart';
import 'presentation/providers/browse_provider.dart';
import 'presentation/providers/sync_provider.dart';
import 'presentation/screens/library_screen.dart';
import 'presentation/services/audio_handler.dart';
import 'presentation/services/playback_stats_recorder.dart';
import 'presentation/services/track_uri_resolver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await AudioService.init(
    builder: () => OwnToneAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.owntone.sync.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    ),
  );
  final dbRepo = LocalDatabaseRepository();
  final playbackController = PlaybackController(
    handler: audioHandler,
    resolver: TrackUriResolver(dbRepo: dbRepo),
  );
  // Records play/skip events straight into pending_events. Lives for the
  // process lifetime, like the handler.
  PlaybackStatsRecorder(
    mediaItem: audioHandler.mediaItem,
    playbackState: audioHandler.playbackState,
    durationStream: audioHandler.durationStream,
    position: AudioService.position,
    consumeUserInitiatedTransition: audioHandler.consumeUserInitiatedTransition,
    insertEvent: dbRepo.insertEvent,
  ).start();
  runApp(MyApp(playbackController: playbackController));
}

class MyApp extends StatelessWidget {
  final PlaybackController playbackController;

  const MyApp({super.key, required this.playbackController});

  @override
  Widget build(BuildContext context) {
    return _buildApp();
  }

  Widget _buildApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        ChangeNotifierProvider(create: (_) => BrowseProvider()),
        Provider<PlaybackController>.value(value: playbackController),
      ],
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
        themeMode: ThemeMode.system,
        home: const LibraryScreen(),
      ),
    );
  }
}
