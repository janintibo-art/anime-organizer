import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../models/anime.dart';
import '../services/library_controller.dart';
import '../services/remote_library.dart';
import 'remote_episodes_screen.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';
import 'folder_picker_screen.dart';
import 'settings_screen.dart';
import 'pc_sync_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  String _source = 'all'; // all | local | pc
  String _genre = '';
  String _category = ''; // '' | anime | western | adult | other
  bool _favoritesOnly = false;
  bool _vfOnly = false;
  String _collection = ''; // '' | todo | watching | done

  bool get _filtering =>
      _query.isNotEmpty ||
      _genre.isNotEmpty ||
      _category.isNotEmpty ||
      _favoritesOnly ||
      _vfOnly ||
      _collection.isNotEmpty;

  @override
  void initState() {
    super.initState();
    remoteLibrary.addListener(_remoteUpdated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupScan();
      remoteLibrary.initialize();
    });
  }

  Future<void> _startupScan() async {
    if (library.folders.isEmpty) return;
    await library.startupScan();
    if (!mounted) return;

    final messages = <String>[];
    if (library.lastNewCount > 0) {
      messages.add(library.lastNewCount == 1
          ? '1 nouvelle série ajoutée'
          : '${library.lastNewCount} nouvelles séries ajoutées');
    }
    if (library.unreachableFolders.isNotEmpty) {
      messages.add(
          '${library.unreachableFolders.length} dossier(s) injoignable(s), fiches conservées');
    }
    if (messages.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(messages.join(' · '))));
  }

  void _remoteUpdated() { if (mounted) setState(() {}); }

  // V43 : évite de filtrer la bibliothèque distante à chaque caractère.
  void _updateSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }


  @override
  void dispose() {
    remoteLibrary.removeListener(_remoteUpdated);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;
    await Permission.videos.request();
    await Permission.storage.request();
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }

  Future<void> _addFolder() async {
    try {
      await _ensurePermissions();
      if (!mounted) return;
      final dir = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
      );
      if (dir == null || dir.trim().isEmpty) return;
      if (!Directory(dir).existsSync()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier introuvable ou inaccessible.')));
        return;
      }
      final alreadyAdded = library.folders.contains(dir);
      await library.addFolder(dir);
      // Si un scan est en cours, le controleur met le nouveau scan en file.
      await library.scan();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        alreadyAdded ? 'Dossier deja present. Analyse demandee.'
            : 'Dossier ajoute. Analyse lancee ou programmee.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ajouter ce dossier : $e')));
    }
  }

  void _open(Anime anime) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailScreen(anime: anime)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        return Scaffold(
          // V39_RESPONSIVE_HEADER: Android shows one menu, never overlapping the title.
          appBar: darkAppBar(
            title: Row(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radiusSm),
                child: Image.asset('assets/icon.png', width: 29, height: 29,
                  fit: BoxFit.cover),
              ),
              const SizedBox(width: 8),
              const Flexible(child: Text('Anime Organizer', maxLines: 1,
                overflow: TextOverflow.ellipsis)),
            ]),
            actions: Platform.isAndroid ? [
              PopupMenuButton<String>(
                tooltip: 'Options',
                icon: const Icon(Icons.more_vert),
                onSelected: (choice) async {
                  switch (choice) {
                    case 'sync':
                      if (!mounted) return;
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PcSyncScreen()));
                      break;
                    case 'folder': await _addFolder(); break;
                    case 'repair':
                      if (library.busy) return;
                      final count = await library.repairWrongMatches();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$count fiche(s) verifiee(s).')));
                      break;
                    case 'scan':
                      if (!library.busy) await library.scan();
                      break;
                    case 'settings':
                      if (!mounted) return;
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SettingsScreen()));
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'sync', child: Text('Connexion au PC')),
                  PopupMenuItem(value: 'folder', child: Text('Ajouter un dossier')),
                  PopupMenuItem(value: 'repair', child: Text('Verifier les fiches')),
                  PopupMenuItem(value: 'scan', child: Text('Actualiser la bibliotheque')),
                  PopupMenuItem(value: 'settings', child: Text('Reglages')),
                ],
              ),
            ] : [
              IconButton(tooltip: 'Synchronisation PC / Android',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PcSyncScreen())),
                icon: const Icon(Icons.sync_alt)),
              IconButton(tooltip: 'Ajouter un dossier', onPressed: _addFolder,
                icon: const Icon(Icons.create_new_folder_outlined)),
              IconButton(tooltip: 'Verifier les fiches incoherentes',
                onPressed: library.busy ? null : () async {
                  final count = await library.repairWrongMatches();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$count fiche(s) corrigee(s).')));
                }, icon: const Icon(Icons.fact_check_outlined)),
              IconButton(tooltip: 'Relancer le scan',
                onPressed: library.busy ? null : () => library.scan(),
                icon: const Icon(Icons.refresh)),
              IconButton(tooltip: 'Reglages',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SettingsScreen())),
                icon: const Icon(Icons.tune)),
            ],
          ),
          floatingActionButton: library.animes.isEmpty
              ? null
              : FloatingActionButton(
                  onPressed: library.busy ? null : _addFolder,
                  backgroundColor: Palette.shu,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.create_new_folder_outlined),
                ),
          body: library.animes.isEmpty && remoteLibrary.series.isEmpty && !remoteLibrary.loading && remoteLibrary.host.isEmpty && !library.busy
              ? _emptyState()
              : Column(
                  children: [
                    if (library.busy) _progressBar(),
                    if (library.animes.isNotEmpty || remoteLibrary.series.isNotEmpty) _filters(),
                    Expanded(child: _content()),
                  ],
                ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- contenu

  Widget _content() {
    final remote = remoteLibrary.series.where((item) {
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        if (!['title', 'folderTitle', 'frenchTitle', 'romajiTitle']
            .any((key) => '${item[key] ?? ''}'.toLowerCase().contains(q))) return false;
      }
      if (_favoritesOnly && item['favorite'] != true) return false;
      if (_collection == 'done' &&
          (item['watchedCount'] ?? 0) != (item['episodeCount'] ?? -1)) return false;
      if (_collection == 'todo' && (item['watchedCount'] ?? 0) != 0) return false;
      if (_collection == 'watching' &&
          ((item['watchedCount'] ?? 0) == 0 ||
           (item['watchedCount'] ?? 0) == (item['episodeCount'] ?? -1))) return false;
      // Le serveur ne transmet pas encore genre, catégorie et VF : ne pas
      // inventer de métadonnées pour répondre à ces filtres.
      if (_genre.isNotEmpty || _category.isNotEmpty || _vfOnly) return false;
      return true;
    }).toList();
    final showRemote = Platform.isAndroid && _source != 'local';
    final showLocal = _source != 'pc';
    if (!showLocal) return _remoteList(remote);
    if (!showRemote || remote.isEmpty) {
      if (showRemote && library.animes.isEmpty &&
          (remoteLibrary.loading || remoteLibrary.host.isNotEmpty)) {
        return _remoteList(remote);
      }
      return _localContent();
    }
    var localItems = library.view(query: _query, genre: _genre,
        favoritesOnly: _favoritesOnly, vfOnly: _vfOnly);
    if (_category.isNotEmpty) {
      localItems = localItems.where((a) => a.category == _category).toList();
    }
    if (_collection.isNotEmpty) {
      localItems = localItems.where((a) => a.collection == _collection).toList();
    }
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: _remoteStatus()),
      _sectionHeader('Bibliothèque du PC', remote.length),
      _remoteSliver(remote),
      if (localItems.isNotEmpty) ...[
        _sectionHeader('Sur ce téléphone', localItems.length),
        SliverList(delegate: SliverChildBuilderDelegate((_, i) =>
          AnimeRow(anime: localItems[i], onTap: () => _open(localItems[i])),
          childCount: localItems.length)),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ]);
  }

  Widget _remoteStatus() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Row(children: [
      Icon(remoteLibrary.connected ? Icons.cloud_done_outlined :
        Icons.cloud_off_outlined, color: remoteLibrary.connected ?
        Palette.kin : Palette.muted, size: 19),
      const SizedBox(width: 8),
      Expanded(child: Text(remoteLibrary.connected
        ? 'PC connecté · ${remoteLibrary.series.length} séries'
        : 'PC hors ligne · catalogue mémorisé',
        style: TextStyle(color: Palette.muted))),
      IconButton(tooltip: 'Actualiser le catalogue PC',
        onPressed: remoteLibrary.loading ? null : remoteLibrary.refresh,
        icon: remoteLibrary.loading
          ? const SizedBox(width: 18, height: 18, child:
              CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh)),
    ]),
  );

  void _openRemote(Map<String, dynamic> item) {
    if (!remoteLibrary.connected) return;
    final id = item['id'];
    if (id is! int) return;
    final title = '${item['title'] ?? item['folderTitle'] ?? 'Sans titre'}';
    Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
      RemoteEpisodesScreen(host: remoteLibrary.host,
        pairCode: remoteLibrary.pairCode,
        seriesId: id, seriesTitle: title)));
  }

  Widget _remotePoster(Map<String, dynamic> item, {double? width,
      double? height}) {
    final url = '${item['imageUrl'] ?? ''}';
    final placeholder = Container(
      width: width, height: height, color: Palette.raised,
      child: const Center(child: Icon(Icons.movie_outlined, size: 32)));
    if (!url.startsWith('https://') && !url.startsWith('http://')) {
      return placeholder;
    }
    // Décode une vignette à la taille d'affichage, et non la jaquette HD.
    return Image.network(url, width: width, height: height,
      fit: BoxFit.cover, cacheWidth: 320,
      errorBuilder: (_, __, ___) => placeholder);
  }

  Widget _remoteTile(Map<String, dynamic> item) {
    final title = '${item['title'] ?? item['folderTitle'] ?? 'Sans titre'}';
    return ListTile(
      leading: ClipRRect(borderRadius: BorderRadius.circular(5),
        child: _remotePoster(item, width: 49, height: 67)),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${item['episodeCount'] ?? 0} épisodes · '
          '${item['watchedCount'] ?? 0} vus · PC'),
      trailing: Icon(remoteLibrary.connected ? Icons.play_circle_outline :
          Icons.cloud_off_outlined, color: Palette.kin),
      onTap: remoteLibrary.connected ? () => _openRemote(item) : null,
    );
  }

  Widget _remoteCard(Map<String, dynamic> item) {
    final title = '${item['title'] ?? item['folderTitle'] ?? 'Sans titre'}';
    return InkWell(
      onTap: remoteLibrary.connected ? () => _openRemote(item) : null,
      borderRadius: BorderRadius.circular(9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(7),
            child: Stack(fit: StackFit.expand, children: [
              _remotePoster(item),
              if (!remoteLibrary.connected)
                const Align(alignment: Alignment.topRight,
                  child: Padding(padding: EdgeInsets.all(6),
                    child: Icon(Icons.cloud_off_outlined, size: 18))),
            ]))),
          const SizedBox(height: 5),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('${item['episodeCount'] ?? 0} épisodes · PC',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Palette.muted)),
        ]),
    );
  }

  // Slivers paresseux : seules les fiches visibles sont construites.
  Widget _remoteSliver(List<Map<String, dynamic>> remote) {
    if (library.settings.viewMode == 'list') {
      return SliverList(delegate: SliverChildBuilderDelegate(
        (_, i) => _remoteTile(remote[i]), childCount: remote.length));
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(builder: (context, constraints) {
        final columns = (constraints.crossAxisExtent / 170).floor().clamp(2, 8);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns, childAspectRatio: 0.52,
            crossAxisSpacing: 12, mainAxisSpacing: 16),
          delegate: SliverChildBuilderDelegate(
            (_, i) => _remoteCard(remote[i]), childCount: remote.length));
      }),
    );
  }

  Widget _remoteList(List<Map<String, dynamic>> remote) {
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: _remoteStatus()),
      if (remote.isEmpty)
        SliverFillRemaining(hasScrollBody: false,
          child: Center(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(remoteLibrary.loading ? 'Connexion au PC…' :
              remoteLibrary.error.isNotEmpty
                ? 'PC indisponible. Vérifie Tailscale et réessaie.'
                : 'Aucune série du PC. Ouvre Synchronisation pour associer le PC.',
              textAlign: TextAlign.center))))
      else
        _remoteSliver(remote),
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ]);
  }

  Widget _localContent() {

    var items = library.view(
      query: _query,
      genre: _genre,
      favoritesOnly: _favoritesOnly,
      vfOnly: _vfOnly,
    );
    if (_category.isNotEmpty) {
      items = items.where((a) => a.category == _category).toList();
    }
    if (_collection.isNotEmpty) {
      items = items.where((a) => a.collection == _collection).toList();
    }

    if (items.isEmpty) {
      return Center(
        child: Text('Aucune série ne correspond à ce filtre.',
            style: TextStyle(color: Palette.muted)),
      );
    }

    final resume = library.continueWatching;
    final favorites = library.favorites;
    final showSections = !_filtering && library.settings.viewMode != 'genre';

    return CustomScrollView(
      slivers: [
        if (showSections && resume.isNotEmpty) ...[
          _sectionHeader('Continuer à regarder', resume.length),
          _shelf(resume),
        ],
        if (showSections && favorites.isNotEmpty) ...[
          _sectionHeader('Favoris', favorites.length),
          _shelf(favorites),
        ],
        if (showSections && (resume.isNotEmpty || favorites.isNotEmpty))
          _sectionHeader('Toute la collection', items.length),
        if (library.settings.viewMode == 'genre' && !_filtering)
          ..._genreSections()
        else if (library.settings.viewMode == 'list')
          _list(items)
        else
          _grid(items),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }

  Widget _sectionHeader(String title, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(
          children: [
            Container(width: 3, height: 15, color: Palette.shu),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('$count',
                style: TextStyle(color: Palette.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Rangee horizontale : les series en cours et les favoris.
  Widget _shelf(List<Anime> items) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 232,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => SizedBox(
            width: 118,
            child: AnimeCard(
              anime: items[i],
              titleSize: 12.5,
              onTap: () => _open(items[i]),
              onFavorite: () => library.toggleFavorite(items[i]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Anime> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = (width / 170).floor().clamp(2, 8);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 0.52,
              crossAxisSpacing: 14,
              mainAxisSpacing: 18,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => AnimeCard(
                anime: items[i],
                onTap: () => _open(items[i]),
                onFavorite: () => library.toggleFavorite(items[i]),
              ),
              childCount: items.length,
            ),
          );
        },
      ),
    );
  }

  Widget _list(List<Anime> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => AnimeRow(anime: items[i], onTap: () => _open(items[i])),
          childCount: items.length,
        ),
      ),
    );
  }

  List<Widget> _genreSections() {
    final grouped = library.groupedByGenre(query: _query, vfOnly: _vfOnly);
    final keys = grouped.keys.toList()..sort();
    final slivers = <Widget>[];
    for (final g in keys) {
      slivers.add(_sectionHeader(g, grouped[g]!.length));
      slivers.add(_shelf(grouped[g]!));
    }
    return slivers;
  }

  // ---------------------------------------------------------------- filtres

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(library.status,
              style: TextStyle(color: Palette.muted, fontSize: 12)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusSm),
            child: LinearProgressIndicator(
              value: library.progress > 0 ? library.progress : null,
              minHeight: 4,
              backgroundColor: Palette.raised,
              color: Palette.shu,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _updateSearch,
                  decoration: fieldDecoration(
                    hintText: 'Chercher un titre, un genre, ou « vf »',
                    prefixIcon: Icon(Icons.search,
                        color: Palette.muted, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close,
                                color: Palette.muted, size: 18),
                            onPressed: () {
                              _searchDebounce?.cancel();
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _viewModeButton(),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (Platform.isAndroid) ...[
                  for (final opt in const [
                    ['all', 'Toutes'], ['local', 'Téléphone'], ['pc', 'PC']
                  ]) ...[
                    _chip(label: opt[1], selected: _source == opt[0],
                      onTap: () => setState(() => _source = opt[0])),
                    const SizedBox(width: 8),
                  ],
                ],
                _sortChip(),
                const SizedBox(width: 8),
                for (final c in const [
                  ['', 'Toutes animations'],
                  ['anime', 'Animés japonais'],
                  ['western', 'Dessins animés'],
                  ['adult', 'Animation adulte'],
                  // V24_UNIDENTIFIED: easy access to files without trusted identification.
                  ['other', 'À identifier / autres'],
                ]) ...[
                  _chip(
                    label: c[1],
                    selected: _category == c[0],
                    onTap: () => setState(() => _category = c[0]),
                  ),
                  const SizedBox(width: 8),
                ],
                const SizedBox(width: 8),
                _chip(
                  label: 'Favoris',
                  selected: _favoritesOnly,
                  onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'VF',
                  selected: _vfOnly,
                  onTap: () => setState(() => _vfOnly = !_vfOnly),
                ),
                const SizedBox(width: 8),
                for (final c in const [
                  ['todo', 'À voir'],
                  ['watching', 'En cours'],
                  ['done', 'Terminés'],
                ]) ...[
                  _chip(
                    label: c[1],
                    selected: _collection == c[0],
                    onTap: () => setState(() =>
                        _collection = _collection == c[0] ? '' : c[0]),
                  ),
                  const SizedBox(width: 8),
                ],
                _chip(
                  label: 'Tous les genres',
                  selected: _genre.isEmpty,
                  onTap: () => setState(() => _genre = ''),
                ),
                for (final g in library.allGenres) ...[
                  const SizedBox(width: 8),
                  _chip(
                    label: g,
                    selected: _genre == g,
                    onTap: () => setState(() => _genre = g),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewModeButton() {
    const modes = {
      'grid': [Icons.grid_view, 'Grille'],
      'list': [Icons.view_list, 'Liste compacte'],
      'genre': [Icons.category_outlined, 'Par genre'],
    };
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in modes.entries)
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: entry.value[1] as String,
              onPressed: () =>
                  library.updateSettings((s) => s.viewMode = entry.key),
              icon: Icon(
                entry.value[0] as IconData,
                color: library.settings.viewMode == entry.key
                    ? Palette.shu
                    : Palette.muted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Palette.shu : Colors.transparent,
          border: Border.all(color: selected ? Palette.shu : Palette.line),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : Palette.muted,
          ),
        ),
      ),
    );
  }

  Widget _sortChip() {
    const labels = {
      'alpha': 'A → Z',
      'genre': 'Par genre',
      'score': 'Mieux notés',
      'popularity': 'Les plus connus',
      'recent': 'Récemment ajoutés',
      'year': 'Année de sortie',
      'episodes': 'Plus d\'épisodes',
    };
    return PopupMenuButton<String>(
      color: Palette.surface,
      onSelected: (v) => library.updateSettings((s) => s.sortMode = v),
      itemBuilder: (_) => labels.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Palette.raised,
          border: Border.all(color: Palette.line),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels[library.settings.sortMode] ?? 'A → Z',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Palette.text,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: Palette.muted),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(Palette.logo, width: 240, fit: BoxFit.contain),
            const SizedBox(height: 24),
            const Text(
              'Ta bibliothèque est vide',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Choisis un dossier contenant tes vidéos. Chaque sous-dossier devient une série, '
              'et les fiches se complètent toutes seules.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.muted, height: 1.4, fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _addFolder,
              style: FilledButton.styleFrom(backgroundColor: Palette.shu),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Choisir un dossier'),
            ),
          ],
        ),
      ),
    );
  }
}
