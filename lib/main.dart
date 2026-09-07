import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';
import 'services/library_controller.dart';

/// Palette : nuit d'encre, accent sakura, jade pour les genres, or pour les notes.
class Palette {
  static const ink = Color(0xFF0D0A14);
  static const surface = Color(0xFF171223);
  static const raised = Color(0xFF221A33);
  static const sakura = Color(0xFFFF4D7E);
  static const jade = Color(0xFF57E1B6);
  static const gold = Color(0xFFF2C14E);
  static const text = Color(0xFFECE7F5);
  static const muted = Color(0xFF9A90B3);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await library.load();
  runApp(const AnimeOrganizerApp());
}

class AnimeOrganizerApp extends StatelessWidget {
  const AnimeOrganizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Palette.ink,
      colorScheme: const ColorScheme.dark(
        primary: Palette.sakura,
        secondary: Palette.jade,
        surface: Palette.surface,
        onSurface: Palette.text,
      ),
    );

    return MaterialApp(
      title: 'Anime Organizer',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        appBarTheme: const AppBarTheme(
          backgroundColor: Palette.ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Palette.text,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
        bottomSheetTheme:
            const BottomSheetThemeData(backgroundColor: Palette.surface),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Palette.raised,
          hintStyle: const TextStyle(color: Palette.muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        textTheme: base.textTheme.apply(
          bodyColor: Palette.text,
          displayColor: Palette.text,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Palette.raised,
          contentTextStyle: TextStyle(color: Palette.text),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
