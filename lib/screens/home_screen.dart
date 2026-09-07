import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../models/anime.dart';
import '../services/library_controller.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _genre = '';
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    await Permission.videos.request();
    await Permission.storage.request();
    var manage = await Permission.manageExternalStorage.status;
    if (!manage.isGranted) {
      manage = await Permission.manageExternalStorage.request();
    }
    return true;
  }

  Future<void> _addFolder() async {
    await _ensurePermissions();
    String? dir;
    try {
      dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisir un dossier d\'animes',
      );
    } catch (_) {
      dir = null;
    }
    if (dir == null) return;
    await library.addFolder(dir);
    await library.scan();
  }

  Future<void> _addFolderManually() async {
    final controller = TextEditingController(
      text: Platform.isAndroid ? '/storage/emulated/0/' : '',
    );
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Saisir un chemin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Utile sur Android quand le selecteur de dossiers ne renvoie pas un chemin lisible.',
              style: TextStyle(color: Palette.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: fieldDecoration(
                hintText: '/storage/emulated/0/Animes',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return;
    if (!Directory(path).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce dossier est introuvable sur l\'appareil.')),
      );
      return;
    }
    await _ensurePermissions();
    await library.addFolder(path);
    await library.scan();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
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
        final items = library.view(
          query: _query,
          genre: _genre,
          favoritesOnly: _favoritesOnly,
        );

        return Scaffold(
          appBar: darkAppBar(
            title: const Text('Anime Organizer'),
            actions: [
              IconButton(
                tooltip: 'Relancer le scan',
                onPressed: library.busy ? null : () => library.scan(),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Reglages',
                onPressed: _openSettings,
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: library.busy ? null : _addFolder,
            backgroundColor: Palette.sakura,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Ajouter un dossier'),
          ),
          body: Column(
            children: [
              if (library.busy) _progressBar(),
              if (library.animes.isNotEmpty) _filters(),
              Expanded(
                child: library.animes.isEmpty
                    ? _emptyState()
                    : items.isEmpty
                        ? _noResult()
                        : _grid(items),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(library.status,
              style: const TextStyle(color: Palette.muted, fontSize: 12)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: library.progress > 0 ? library.progress : null,
              minHeight: 4,
              backgroundColor: Palette.raised,
              color: Palette.sakura,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    final genres = library.allGenres;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: fieldDecoration(
              hintText: 'Chercher un titre ou un genre',
              prefixIcon: const Icon(Icons.search, color: Palette.muted),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, color: Palette.muted),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _sortChip(),
                const SizedBox(width: 8),
                _chip(
                  label: 'Favoris',
                  selected: _favoritesOnly,
                  onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'Tous les genres',
                  selected: _genre.isEmpty,
                  onTap: () => setState(() => _genre = ''),
                ),
                for (final g in genres) ...[
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
          color: selected ? Palette.sakura : Palette.raised,
          borderRadius: BorderRadius.circular(20),
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
      'score': 'Mieux notes',
      'year': 'Plus recents',
      'episodes': 'Plus d\'episodes',
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
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels[library.settings.sortMode] ?? 'A → Z',
              style: const TextStyle(
                  fontSize: 12.5, color: Palette.text, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 16, color: Palette.muted),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Anime> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.52,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => AnimeCard(
            anime: items[i],
            onTap: () => _open(items[i]),
            onFavorite: () => library.toggleFavorite(items[i]),
          ),
        );
      },
    );
  }

  Widget _noResult() {
    return const Center(
      child: Text(
        'Aucune serie ne correspond a ce filtre.',
        style: TextStyle(color: Palette.muted),
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
            const Icon(Icons.folder_open, size: 48, color: Palette.raised),
            const SizedBox(height: 16),
            const Text(
              'Ta bibliotheque est vide',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choisis un dossier contenant tes videos. Chaque sous-dossier devient une serie, '
              'et les fiches sont completees automatiquement.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.muted, height: 1.4, fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _addFolder,
              style: FilledButton.styleFrom(backgroundColor: Palette.sakura),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Choisir un dossier'),
            ),
            TextButton(
              onPressed: _addFolderManually,
              child: const Text('Saisir un chemin a la main',
                  style: TextStyle(color: Palette.jade)),
            ),
          ],
        ),
      ),
    );
  }
}
