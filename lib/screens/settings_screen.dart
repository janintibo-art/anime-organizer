import 'package:flutter/material.dart';

import '../main.dart';
import '../services/library_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _key =
      TextEditingController(text: library.settings.apiKey);
  late final TextEditingController _endpoint =
      TextEditingController(text: library.settings.libreEndpoint);
  late final TextEditingController _email =
      TextEditingController(text: library.settings.email);

  @override
  void dispose() {
    _key.dispose();
    _endpoint.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final s = library.settings;
        return Scaffold(
          appBar: darkAppBar(title: const Text('Réglages')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _section('Dossiers surveillés'),
              if (library.folders.isEmpty)
                const Text('Aucun dossier pour l\'instant.',
                    style: TextStyle(color: Palette.muted, fontSize: 13)),
              for (final f in library.folders)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined, color: Palette.kin),
                  title: Text(f, style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Palette.muted),
                    onPressed: () => _confirmRemoveFolder(f),
                  ),
                ),

              const SizedBox(height: 20),
              _section('Traduction des synopsis'),
              _dropdown<String>(
                label: 'Service',
                value: s.translationProvider,
                items: const {
                  'none': 'Aucune traduction',
                  'mymemory': 'MyMemory (gratuit, sans clé)',
                  'libretranslate': 'LibreTranslate',
                  'deepl': 'DeepL (clé requise)',
                },
                onChanged: (v) =>
                    library.updateSettings((s) => s.translationProvider = v),
              ),
              _dropdown<String>(
                label: 'Langue cible',
                value: s.targetLang,
                items: const {
                  'fr': 'Français',
                  'es': 'Espagnol',
                  'de': 'Allemand',
                  'it': 'Italien',
                  'pt': 'Portugais',
                  'nl': 'Néerlandais',
                },
                onChanged: (v) => library.updateSettings((s) => s.targetLang = v),
              ),
              if (s.translationProvider == 'mymemory')
                _field(
                  controller: _email,
                  label: 'Email (facultatif)',
                  hint: 'Passe le quota de 5 000 a 50 000 caractères par jour',
                  onSubmit: (v) => library.updateSettings((s) => s.email = v),
                ),
              if (s.translationProvider == 'libretranslate')
                _field(
                  controller: _endpoint,
                  label: 'Adresse du serveur',
                  hint: 'https://libretranslate.com',
                  onSubmit: (v) => library.updateSettings((s) => s.libreEndpoint = v),
                ),
              if (s.translationProvider == 'libretranslate' ||
                  s.translationProvider == 'deepl')
                _field(
                  controller: _key,
                  label: 'Clé API',
                  hint: 'Collee depuis ton compte',
                  onSubmit: (v) => library.updateSettings((s) => s.apiKey = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: Palette.shu,
                value: s.autoTranslate,
                onChanged: (v) => library.updateSettings((s) => s.autoTranslate = v),
                title: const Text('Traduire pendant le scan',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                    'Plus lent, mais les fiches sont pretes tout de suite.',
                    style: TextStyle(color: Palette.muted, fontSize: 12)),
              ),

              const SizedBox(height: 12),
              _section('Fiches'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: Palette.shu,
                value: s.scanOnStart,
                onChanged: (v) => library.updateSettings((s) => s.scanOnStart = v),
                title: const Text('Scanner à chaque ouverture',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                    'Détecte les nouveaux animes. Les fiches déjà trouvées sont conservées.',
                    style: TextStyle(color: Palette.muted, fontSize: 12)),
              ),
              _dropdown<String>(
                label: 'Source des métadonnées',
                value: s.metaSource,
                items: const {
                  'auto': 'AniList, puis MyAnimeList si besoin',
                  'anilist': 'AniList seulement',
                  'jikan': 'MyAnimeList seulement',
                },
                onChanged: (v) => library.updateSettings((s) => s.metaSource = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: Palette.shu,
                value: s.autoFetch,
                onChanged: (v) => library.updateSettings((s) => s.autoFetch = v),
                title: const Text('Chercher images et descriptions',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text('Images, synopsis, genres, notés et studios.',
                    style: TextStyle(color: Palette.muted, fontSize: 12)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: library.busy ? null : () => library.retryFailed(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Compléter les fiches manquantes'),
                  ),
                  OutlinedButton.icon(
                    onPressed: library.busy ? null : () => library.translateAll(),
                    icon: const Icon(Icons.translate, size: 18),
                    label: const Text('Tout traduire'),
                  ),
                  OutlinedButton.icon(
                    onPressed: library.busy ? null : _confirmClear,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Vider la bibliothèque'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'Les vidéos restent sur ton disque : l\'application ne fait que les lister et les lire. '
                'Seuls les titres sont envoyés aux services de métadonnées et de traduction.',
                style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRemoveFolder(String folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Retirer ce dossier ?'),
        content: Text(
          'Les séries de $folder disparaîtront de la bibliothèque. '
          'Aucun fichier video n'est supprimé du disque.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (ok == true) await library.removeFolder(folder);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Vider la bibliothèque ?'),
        content: const Text(
            'Les fiches et les favoris seront effacés. Tes fichiers video ne sont pas touchés.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vider'),
          ),
        ],
      ),
    );
    if (ok == true) await library.clearLibrary();
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 6),
        child: Row(
          children: [
            Container(width: 3, height: 16, color: Palette.shu),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: fieldDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: Palette.raised,
            style: const TextStyle(color: Palette.text, fontSize: 14),
            items: items.entries
                .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onSubmit,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        onChanged: onSubmit,
        decoration: fieldDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}
