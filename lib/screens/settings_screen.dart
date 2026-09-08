import 'package:flutter/material.dart';

import '../main.dart';
import '../services/library_controller.dart';
import '../services/ai_service.dart';
import '../services/diagnostics.dart';
import '../services/anime_index.dart';
import '../services/seed_database.dart';
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
  late final TextEditingController _aiKey =
      TextEditingController(text: library.settings.aiKey);
  late final TextEditingController _aiModel =
      TextEditingController(text: library.settings.aiModel);
  late final TextEditingController _aiEndpoint =
      TextEditingController(text: library.settings.aiEndpoint);

  late final TextEditingController _audioLang =
      TextEditingController(text: library.settings.preferredAudio);
  late final TextEditingController _subLang =
      TextEditingController(text: library.settings.preferredSubtitle);
  late final TextEditingController _tmdbKey =
      TextEditingController(text: library.settings.tmdbKey);

  List<String> _models = [];
  List<String> _diagnostic = [];
  bool _diagBusy = false;

  bool _indexBusy = false;
  double _indexProgress = 0;
  String? _indexMessage;
  int _indexBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshIndexSize();
  }

  Future<void> _refreshIndexSize() async {
    final bytes = await AnimeIndex.sizeInBytes();
    if (mounted) setState(() => _indexBytes = bytes);
  }
  String? _aiMessage;
  bool _aiBusy = false;

  @override
  void dispose() {
    _key.dispose();
    _endpoint.dispose();
    _email.dispose();
    _aiKey.dispose();
    _aiModel.dispose();
    _aiEndpoint.dispose();
    _audioLang.dispose();
    _subLang.dispose();
    _tmdbKey.dispose();
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
                icon: Icons.storage,
                title: 'Base locale',
                children: [
                  Text(
                    '${SeedDatabase.count} séries connues hors connexion, avec leurs titres '
                    'en romaji, anglais, français et japonais. Elles servent à traduire un nom '
                    'de dossier en titre que les bases en ligne reconnaissent.',
                    style: const TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${library.knownTitles.length} correspondance(s) mémorisée(s) '
                    'depuis tes corrections. Ces dossiers ne seront plus recherchés.',
                    style: const TextStyle(
                        color: Palette.kin, fontSize: 12, height: 1.4),
                  ),
                  if (library.knownTitles.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _forgetTitles,
                      icon: const Icon(Icons.backspace_outlined, size: 18),
                      label: const Text('Oublier les correspondances'),
                    ),
                  ],
                  const Divider(color: Palette.line, height: 28),
                  _indexSection(),
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
                      'auto': 'Automatique — les cinq sources en cascade',
                      'anilist': 'AniList seulement',
                      'jikan': 'MyAnimeList seulement',
                      'kitsu': 'Kitsu seulement',
                      'animethemes': 'AnimeThemes seulement',
                      'tmdb': 'TMDB seulement (clé requise)',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.metaSource = v),
                  ),
                  _field(
                    controller: _tmdbKey,
                    label: 'Clé TMDB (facultative)',
                    hint: 'themoviedb.org — gratuite, donne des synopsis en français',
                    obscure: true,
                    onSubmit: (v) => library.updateSettings((s) => s.tmdbKey = v),
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
                icon: Icons.play_circle_outline,
                title: 'Lecteur',
                children: [
                  _switch(
                    value: s.autoNext,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.autoNext = v),
                    title: 'Enchaîner les épisodes',
                    subtitle:
                        'Sinon la lecture s\'arrête à la fin de chaque épisode.',
                  ),
                  _dropdown<int>(
                    label: 'Bouton « passer l\'intro »',
                    value: const [60, 85, 90, 120].contains(s.skipIntroSeconds)
                        ? s.skipIntroSeconds
                        : 85,
                    items: const {
                      60: '60 secondes',
                      85: '85 secondes (générique classique)',
                      90: '90 secondes',
                      120: '2 minutes',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.skipIntroSeconds = v),
                  ),
                  _field(
                    controller: _audioLang,
                    label: 'Langue audio préférée',
                    hint: 'jpn, fre, eng… laisser vide pour ne rien forcer',
                    onSubmit: (v) =>
                        library.updateSettings((s) => s.preferredAudio = v),
                  ),
                  _field(
                    controller: _subLang,
                    label: 'Sous-titres préférés',
                    hint: 'fr, fre, vostfr…',
                    onSubmit: (v) =>
                        library.updateSettings((s) => s.preferredSubtitle = v),
                  ),
                  const Text(
                    'Les fichiers .srt ou .ass posés à côté des vidéos sont chargés automatiquement.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
              _card(
                icon: Icons.auto_awesome,
                title: 'Assistant IA',
                children: [
                  const Text(
                    'Quand AniList et MyAnimeList ne reconnaissent pas un dossier, '
                    'l\'IA identifie la série et donne son titre en romaji, en anglais, '
                    'en français et en japonais.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  _switch(
                    value: s.aiEnabled,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.aiEnabled = v),
                    title: 'Utiliser l\'IA en dernier recours',
                    subtitle:
                        'Uniquement quand la recherche classique échoue.',
                  ),
                  _dropdown<String>(
                    label: 'Fournisseur',
                    value: s.aiProvider,
                    items: const {
                      'groq': 'Groq — gratuit, sans carte bancaire',
                      'openrouter': 'OpenRouter',
                      'custom': 'Serveur compatible OpenAI',
                    },
                    onChanged: (v) {
                      library.updateSettings((s) => s.aiProvider = v);
                      setState(() => _models = []);
                    },
                  ),
                  if (s.aiProvider == 'custom')
                    _field(
                      controller: _aiEndpoint,
                      label: 'Adresse du serveur',
                      hint: 'https://mon-serveur/v1',
                      onSubmit: (v) =>
                          library.updateSettings((s) => s.aiEndpoint = v),
                    ),
                  _field(
                    controller: _aiKey,
                    label: 'Clé d\'API',
                    hint: s.aiProvider == 'groq'
                        ? 'console.groq.com — clé gratuite'
                        : 'Collée depuis ton compte',
                    obscure: true,
                    onSubmit: (v) => library.updateSettings((s) => s.aiKey = v),
                  ),
                  if (_models.isEmpty)
                    _field(
                      controller: _aiModel,
                      label: 'Modèle',
                      hint: 'llama-3.3-70b-versatile',
                      onSubmit: (v) =>
                          library.updateSettings((s) => s.aiModel = v),
                    )
                  else
                    _dropdown<String>(
                      label: 'Modèle',
                      value: _models.contains(s.aiModel)
                          ? s.aiModel
                          : _models.first,
                      items: {for (final m in _models) m: m},
                      onChanged: (v) {
                        _aiModel.text = v;
                        library.updateSettings((s) => s.aiModel = v);
                      },
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _aiBusy ? null : _loadModels,
                        icon: const Icon(Icons.list_alt, size: 18),
                        label: const Text('Charger les modèles'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _aiBusy ? null : _testAi,
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('Tester la connexion'),
                      ),
                    ],
                  ),
                  if (_aiBusy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Palette.raised,
                          color: Palette.shu),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Conseil : les modèles « gpt-oss » réfléchissent avant de répondre '
                      'et consomment beaucoup de jetons. « llama-3.3-70b-versatile » '
                      'répond directement et convient mieux ici.',
                      style: TextStyle(
                          color: Palette.muted, fontSize: 11.5, height: 1.4),
                    ),
                  ),
                  if (_aiMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_aiMessage!,
                          style: const TextStyle(
                              color: Palette.kin, fontSize: 12, height: 1.4)),
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
                icon: Icons.network_check,
                title: 'Diagnostic',
                children: [
                  const Text(
                    'Vérifie que l\'application atteint bien Internet et les deux bases de données. '
                    'À lancer si aucune image ni description n\'apparaît.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _diagBusy ? null : _runDiagnostic,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Tester la connexion'),
                  ),
                  if (_diagBusy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Palette.raised,
                          color: Palette.shu),
                    ),
                  for (final line in _diagnostic)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: line.contains('OK') ? Palette.kin : Palette.shu,
                        ),
                      ),
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

  Widget _indexSection() {
    final installed = _indexBytes > 0;
    final loaded = AnimeIndex.isLoaded;
    final generated = AnimeIndex.meta['generated']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Index complet',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'Environ 40 000 séries avec leurs synonymes et leurs affiches, '
          'reconstruites chaque semaine par ton dépôt GitHub. Une fois '
          'téléchargé, il répond sans connexion.',
          style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 10),
        Text(
          !installed
              ? 'Non téléchargé.'
              : loaded
                  ? '${AnimeIndex.count} séries chargées · '
                      '${(_indexBytes / 1000000).toStringAsFixed(1)} Mo'
                      '${generated == null ? '' : ' · version $generated'}'
                  : '${(_indexBytes / 1000000).toStringAsFixed(1)} Mo sur le disque, chargement en cours.',
          style: TextStyle(
              color: installed ? Palette.kin : Palette.muted, fontSize: 12),
        ),
        if (_indexBusy) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusSm),
            child: LinearProgressIndicator(
              value: _indexProgress > 0 ? _indexProgress : null,
              minHeight: 4,
              backgroundColor: Palette.raised,
              color: Palette.shu,
            ),
          ),
        ],
        if (_indexMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_indexMessage!,
                style: const TextStyle(
                    color: Palette.kin, fontSize: 12, height: 1.4)),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _indexBusy ? null : _downloadIndex,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(installed ? 'Mettre à jour' : 'Télécharger'),
            ),
            if (installed)
              OutlinedButton.icon(
                onPressed: _indexBusy ? null : _removeIndex,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Supprimer'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Données : manami-project / anime-offline-database, '
          'sous licence ODbL 1.0 et CC BY-SA 4.0.',
          style: TextStyle(color: Palette.muted, fontSize: 10.5, height: 1.4),
        ),
      ],
    );
  }

  Future<void> _downloadIndex() async {
    setState(() {
      _indexBusy = true;
      _indexProgress = 0;
      _indexMessage = null;
    });

    final ok = await AnimeIndex.download(
      repo: library.settings.indexRepo,
      onProgress: (received, total) {
        if (!mounted || total <= 0) return;
        setState(() => _indexProgress = received / total);
      },
    );

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _indexBusy = false;
        _indexMessage = AnimeIndex.lastError ?? 'Téléchargement impossible.';
      });
      return;
    }

    setState(() {
      _indexProgress = 0;
      _indexMessage = 'Chargement de l\'index…';
    });
    final loaded = await AnimeIndex.load();
    await _refreshIndexSize();
    if (!mounted) return;
    setState(() {
      _indexBusy = false;
      _indexMessage = loaded
          ? '${AnimeIndex.count} séries disponibles hors connexion.'
          : (AnimeIndex.lastError ?? 'Index illisible.');
    });
  }

  Future<void> _removeIndex() async {
    await AnimeIndex.remove();
    await _refreshIndexSize();
    if (!mounted) return;
    setState(() => _indexMessage = 'Index supprimé.');
  }

  Future<void> _forgetTitles() async {
    library.knownTitles.clear();
    await library.save();
    library.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Correspondances oubliées.')),
    );
  }

  Future<void> _runDiagnostic() async {
    setState(() {
      _diagBusy = true;
      _diagnostic = [];
    });
    final lines = await Diagnostics.run();
    lines.addAll(Diagnostics.lastErrors());
    if (!mounted) return;
    setState(() {
      _diagBusy = false;
      _diagnostic = lines;
    });
  }

  Future<void> _loadModels() async {
    setState(() {
      _aiBusy = true;
      _aiMessage = null;
    });
    final models = await AiService.listModels(
      provider: library.settings.aiProvider,
      apiKey: _aiKey.text.trim(),
      custom: _aiEndpoint.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _aiBusy = false;
      _models = models;
      _aiMessage = models.isEmpty
          ? 'Aucun modèle reçu. Vérifie la clé et la connexion.'
          : '${models.length} modèles disponibles.';
    });
  }

  Future<void> _testAi() async {
    setState(() {
      _aiBusy = true;
      _aiMessage = null;
    });
    final result = await AiService.test(
      provider: library.settings.aiProvider,
      apiKey: _aiKey.text.trim(),
      model: _aiModel.text.trim(),
      custom: _aiEndpoint.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _aiBusy = false;
      _aiMessage = result;
    });
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
