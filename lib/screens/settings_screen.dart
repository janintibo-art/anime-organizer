import 'package:flutter/material.dart';

import '../main.dart';
import '../services/library_controller.dart';
import '../services/poster_cache.dart';
import 'bulk_fix_screen.dart';
import 'folder_picker_screen.dart';

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
              _card(
                icon: Icons.folder_copy_outlined,
                title: 'Bibliothèque',
                children: [
                  if (library.folders.isEmpty)
                    const Text('Aucun dossier pour l\'instant.',
                        style: TextStyle(color: Palette.muted, fontSize: 13)),
                  for (final f in library.folders)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading:
                          const Icon(Icons.folder_outlined, color: Palette.kin),
                      title: Text(f, style: const TextStyle(fontSize: 12.5)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close,
                            color: Palette.muted, size: 18),
                        onPressed: () => _confirmRemoveFolder(f),
                      ),
                    ),
                  _switch(
                    value: s.scanOnStart,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.scanOnStart = v),
                    title: 'Scanner à chaque ouverture',
                    subtitle:
                        'Détecte les nouveaux animes. Les fiches déjà trouvées sont conservées.',
                  ),
                ],
              ),
              _card(
                icon: Icons.badge_outlined,
                title: 'Métadonnées',
                children: [
                  _dropdown<String>(
                    label: 'Source',
                    value: s.metaSource,
                    items: const {
                      'auto': 'AniList, puis MyAnimeList si besoin',
                      'anilist': 'AniList seulement',
                      'jikan': 'MyAnimeList seulement',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.metaSource = v),
                  ),
                  _switch(
                    value: s.autoFetch,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.autoFetch = v),
                    title: 'Chercher images et descriptions',
                    subtitle: 'Images, synopsis, genres, notes et studios.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            library.busy ? null : () => library.retryFailed(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Compléter les fiches manquantes'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const BulkFixScreen()),
                        ),
                        icon: const Icon(Icons.edit_note, size: 18),
                        label: Text(
                            'Corriger ${library.unmatched.length} fiche(s)'),
                      ),
                    ],
                  ),
                ],
              ),
              _card(
                icon: Icons.translate,
                title: 'Traduction',
                children: [
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
                    onChanged: (v) =>
                        library.updateSettings((s) => s.targetLang = v),
                  ),
                  if (s.translationProvider == 'mymemory')
                    _field(
                      controller: _email,
                      label: 'Email (facultatif)',
                      hint: 'Fait passer le quota de 5 000 à 50 000 caractères par jour',
                      onSubmit: (v) => library.updateSettings((s) => s.email = v),
                    ),
                  if (s.translationProvider == 'libretranslate')
                    _field(
                      controller: _endpoint,
                      label: 'Adresse du serveur',
                      hint: 'https://libretranslate.com',
                      onSubmit: (v) =>
                          library.updateSettings((s) => s.libreEndpoint = v),
                    ),
                  if (s.translationProvider == 'libretranslate' ||
                      s.translationProvider == 'deepl')
                    _field(
                      controller: _key,
                      label: 'Clé API',
                      hint: 'Collée depuis ton compte',
                      obscure: true,
                      onSubmit: (v) => library.updateSettings((s) => s.apiKey = v),
                    ),
                  _switch(
                    value: s.autoTranslate,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.autoTranslate = v),
                    title: 'Traduire pendant le scan',
                    subtitle: 'Plus lent, mais les fiches sont prêtes tout de suite.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        library.busy ? null : () => library.translateAll(),
                    icon: const Icon(Icons.translate, size: 18),
                    label: const Text('Tout traduire'),
                  ),
                ],
              ),
              _card(
                icon: Icons.cloud_off_outlined,
                title: 'Hors connexion',
                children: [
                  _switch(
                    value: s.offlinePosters,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.offlinePosters = v),
                    title: 'Enregistrer les affiches sur l\'appareil',
                    subtitle:
                        'La bibliothèque reste illustrée sans connexion.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: library.busy ? null : _cachePosters,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Télécharger les affiches'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearPosters,
                        icon: const Icon(Icons.cleaning_services_outlined,
                            size: 18),
                        label: const Text('Vider le cache d\'affiches'),
                      ),
                    ],
                  ),
                ],
              ),
              _card(
                icon: Icons.save_outlined,
                title: 'Sauvegarde',
                children: [
                  const Text(
                    'Un fichier unique contient les fiches, les favoris et la progression. '
                    'Les vidéos ne sont pas copiées.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _export,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Exporter'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restaurer'),
                      ),
                    ],
                  ),
                ],
              ),
              _card(
                icon: Icons.palette_outlined,
                title: 'Apparence',
                children: [
                  _dropdown<String>(
                    label: 'Affichage de la collection',
                    value: s.viewMode,
                    items: const {
                      'grid': 'Grille d\'affiches',
                      'list': 'Liste compacte',
                      'genre': 'Rayons par genre',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.viewMode = v),
                  ),
                ],
              ),
              _dangerZone(),
              const SizedBox(height: 20),
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

  // ------------------------------------------------------------------ blocs

  Widget _card({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 15, color: Palette.shu),
              const SizedBox(width: 8),
              Icon(icon, size: 17, color: Palette.kin),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _dangerZone() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0x14BF2F25),
        border: Border.all(color: Palette.shu),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.warning_amber_rounded, size: 17, color: Palette.shu),
              SizedBox(width: 8),
              Text('Actions sensibles',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Palette.shu)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Ces actions effacent des données de l\'application. Tes fichiers vidéo ne sont jamais touchés.',
            style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.shu,
              side: const BorderSide(color: Palette.shu),
            ),
            onPressed: library.busy ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Vider la bibliothèque'),
          ),
        ],
      ),
    );
  }

  Future<void> _cachePosters() async {
    final count = await library.cachePosters();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count affiche(s) enregistrée(s).')),
    );
  }

  Future<void> _clearPosters() async {
    final count = await PosterCache.clear();
    for (final a in library.animes) {
      a.posterPath = null;
    }
    await library.save();
    library.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count fichier(s) supprimé(s).')),
    );
  }

  Future<void> _export() async {
    final folder = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
    );
    if (folder == null) return;
    try {
      final path = await library.exportLibrary(folder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sauvegarde écrite : $path')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Écriture impossible dans ce dossier.')),
      );
    }
  }

  Future<void> _import() async {
    final file = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const FolderPickerScreen(pickExtension: '.json'),
      ),
    );
    if (file == null || !mounted) return;

    final merge = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Restaurer cette sauvegarde ?'),
        content: const Text(
          'Fusionner conserve ta bibliothèque actuelle et y ajoute les fiches et la progression du fichier. '
          'Remplacer efface tout et repart de la sauvegarde.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Remplacer',
                  style: TextStyle(color: Palette.shu))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fusionner'),
          ),
        ],
      ),
    );
    if (merge == null) return;

    try {
      final count = await library.importLibrary(file, merge: merge);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count série(s) restaurée(s).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fichier de sauvegarde illisible.')),
      );
    }
  }

  Future<void> _confirmRemoveFolder(String folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Retirer ce dossier ?'),
        content: Text(
          'Les séries de $folder disparaîtront de la bibliothèque. '
          'Aucun fichier vidéo n\'est supprimé du disque.',
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
            'Les fiches, les favoris et la progression seront effacés. Tes fichiers vidéo ne sont pas touchés.'),
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

  Widget _switch({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required String subtitle,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Palette.muted, fontSize: 12)),
    );
  }

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
                .map((e) =>
                    DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
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
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        // On enregistre a la validation plutot qu'a chaque frappe.
        onEditingComplete: () => onSubmit(controller.text),
        onSubmitted: onSubmit,
        onTapOutside: (_) => onSubmit(controller.text),
        decoration: fieldDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}
