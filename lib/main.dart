import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'presentation/providers/sync_provider.dart';
import 'presentation/screens/main_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
