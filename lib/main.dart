import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/splash_screen.dart';
import 'services/library_controller.dart';
import 'services/seed_database.dart';

/// Palette calee sur le logo : noir d'encre chaud, rouge de sceau,
/// or et ivoire, avec un rose sakura utilise avec parcimonie.
class Palette {
  static const ink = Color(0xFF0D0B0B);
  static const surface = Color(0xFF181311);
  static const raised = Color(0xFF221A17);
  static const line = Color(0xFF352724);
  static const shu = Color(0xFFBF2F25);
  static const kin = Color(0xFFD6B86A);
  static const sakura = Color(0xFFE3A2AB);
  static const text = Color(0xFFF4E7D3);
  static const muted = Color(0xFF9C8A80);
}

/// Arrondis : deux valeurs seulement, pour que tout l'ecran respire pareil.
const double radiusSm = 4; // puces, badges, champs
const double radiusMd = 8; // affiches, cartes, boites de dialogue

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
    borderRadius: BorderRadius.circular(radiusSm),
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
  await SeedDatabase.load();
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
        secondary: Palette.kin,
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
      home: const SplashScreen(),
    );
  }
}
