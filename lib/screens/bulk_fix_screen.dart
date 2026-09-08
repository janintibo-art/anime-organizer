import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/anime.dart';
import '../models/anime_meta.dart';
import '../services/library_controller.dart';
import '../services/metadata_service.dart';

/// Correction groupée : toutes les séries non identifiées au même endroit,
/// avec un champ de recherche par ligne. Elles disparaissent une fois réglées.
class BulkFixScreen extends StatefulWidget {
  const BulkFixScreen({super.key});

  @override
  State<BulkFixScreen> createState() => _BulkFixScreenState();
}

class _BulkFixScreenState extends State<BulkFixScreen> {
  final Map<String, TextEditingController> _controllers = {};
  String? _searchingId;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Anime anime) {
    return _controllers.putIfAbsent(
      anime.id,
      () => TextEditingController(text: anime.folderTitle),
    );
  }

  Future<void> _search(Anime anime) async {
    final query = _controllerFor(anime).text.trim();
    if (query.isEmpty) return;

    setState(() => _searchingId = anime.id);
    final results = await MetadataService.searchMany(
      query,
      source: library.settings.metaSource,
    );
    if (!mounted) return;
    setState(() => _searchingId = null);

    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun résultat pour ce titre.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<AnimeMeta>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (ctx) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: results.length,
        itemBuilder: (_, i) {
          final r = results[i];
          return ListTile(
            leading: r.imageUrl == null
                ? const Icon(Icons.movie_outlined, color: Palette.muted)
                : SizedBox(
                    width: 40,
                    child: CachedNetworkImage(
                        imageUrl: r.imageUrl!, fit: BoxFit.cover)),
            title: Text(r.title, style: const TextStyle(fontSize: 14)),
            subtitle: Text(r.summaryLine,
                style: const TextStyle(color: Palette.muted, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, r),
          );
        },
      ),
    );
    if (chosen == null) return;

    library.applyMeta(anime, chosen);
    library.remember(anime.folderTitle, chosen.titleRomaji ?? chosen.title);
    await library.save();
    if (library.settings.autoTranslate) {
      await library.translateOne(anime);
    }
    library.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final items = library.unmatched;

        return Scaffold(
          appBar: darkAppBar(title: const Text('Fiches à corriger')),
          body: items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Toutes les séries ont été identifiées.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Palette.muted),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (library.busy)
                      const LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Palette.raised,
                          color: Palette.shu),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${items.length} série${items.length > 1 ? 's' : ''} sans fiche',
                              style: const TextStyle(
                                  color: Palette.muted, fontSize: 12.5),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: library.busy
                                ? null
                                : () => library.retryFailed(),
                            icon: const Icon(Icons.auto_mode, size: 16),
                            label: const Text('Tout relancer',
                                style: TextStyle(fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _row(items[i]),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _row(Anime anime) {
    final searching = _searchingId == anime.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            anime.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Palette.muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controllerFor(anime),
                  onSubmitted: (_) => _search(anime),
                  decoration: fieldDecoration(hintText: 'Titre à rechercher'),
                ),
              ),
              const SizedBox(width: 8),
              searching
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Palette.shu),
                    )
                  : IconButton(
                      onPressed: () => _search(anime),
                      icon: const Icon(Icons.search, color: Palette.shu),
                    ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${anime.episodes.length} fichier${anime.episodes.length > 1 ? 's' : ''}'
            '${anime.metaFailCount > 0 ? ' · ${anime.metaFailCount} tentative(s)' : ''}',
            style: const TextStyle(color: Palette.muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
