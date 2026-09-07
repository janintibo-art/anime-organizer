import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';
import 'services/library_controller.dart';

/// Palette inspiree des couleurs traditionnelles japonaises :
/// nuit d'encre bleutee, vermillon de sceau (shu), bleu-vert asagi,
/// or (kin) et blanc casse facon papier (kinari).
class Palette {
  static const ink = Color(0xFF0A0C12);
  static const surface = Color(0xFF131722);
  static const raised = Color(0xFF1C2130);
  static const line = Color(0xFF2A3142);
  static const shu = Color(0xFFE0473A);
  static const asagi = Color(0xFF6FBFB4);
  static const kin = Color(0xFFD9A93E);
  static const text = Color(0xFFF0EADF);
  static const muted = Color(0xFF888FA3);
}

/// Decoration commune des champs de saisie.
/// Definie ici plutot que dans le theme : l'API du theme change souvent
/// d'une version de Flutter a l'autre, celle-ci est stable.
InputDecoration fieldDecoration({
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: const BorderSide(color: Palette.line),
  );
  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Palette.surface,
    hintStyle: const TextStyle(color: Palette.muted, fontSize: 12.5),
    labelStyle: const TextStyle(color: Palette.muted, fontSize: 13),
    border: border,
    enabledBorder: border,
    focusedBorder: border,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
}

/// Barre de titre commune a tous les ecrans.
AppBar darkAppBar({required Widget title, List<Widget>? actions}) {
  return AppBar(
    title: title,
    actions: actions,
    backgroundColor: Palette.ink,
    surfaceTintColor: Colors.transparent,
    foregroundColor: Palette.text,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: const TextStyle(
      color: Palette.text,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
  );
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
        primary: Palette.shu,
        secondary: Palette.asagi,
        surface: Palette.surface,
        onSurface: Palette.text,
      ),
    );

    return MaterialApp(
      title: 'Anime Organizer',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        bottomSheetTheme:
            const BottomSheetThemeData(backgroundColor: Palette.surface),
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
