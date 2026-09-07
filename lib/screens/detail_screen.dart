import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/anime.dart';
import '../models/anime_meta.dart';
import '../services/metadata_service.dart';
import '../services/library_controller.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final Anime anime;
  const DetailScreen({super.key, required this.anime});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _working = false;
  bool _showOriginal = false;

  Anime get anime => widget.anime;

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _working = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _translate() async {
    await _run(() async {
      final ok = await library.translateOne(anime);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Traduction indisponible. Vérifie le fournisseur dans les réglages.')),
        );
      }
    }, 'La traduction a échoué.');
  }

  Future<void> _searchAgain() async {
    final controller = TextEditingController(text: anime.folderTitle);
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Corriger la fiche'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: fieldDecoration(hintText: 'Titre à rechercher'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Chercher'),
          ),
        ],
      ),
    );
    if (query == null || query.isEmpty) return;

    setState(() => _working = true);
    final results = await MetadataService.searchMany(
      query,
      source: library.settings.metaSource,
    );
    if (!mounted) return;
    setState(() => _working = false);

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
            subtitle: Text(
              r.summaryLine,
              style: const TextStyle(color: Palette.muted, fontSize: 12),
            ),
            onTap: () => Navigator.pop(ctx, r),
          );
        },
      ),
    );
    if (chosen == null) return;

    await _run(() async {
      library.applyMeta(anime, chosen);
      await library.save();
      if (library.settings.autoTranslate) {
        await library.translateOne(anime);
      }
      library.refresh();
    }, 'Impossible d\'appliquer la fiche.');
  }

  void _play(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          title: anime.title,
          episodes: anime.episodes,
          startIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final synopsis = _showOriginal ? anime.synopsisEn : anime.synopsis;

        return Scaffold(
          appBar: darkAppBar(
            title: Text(anime.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                onPressed: () => library.toggleFavorite(anime),
                icon: Icon(
                  anime.favorite ? Icons.favorite : Icons.favorite_border,
                  color: anime.favorite ? Palette.sakura : Palette.text,
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              if (_working)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Palette.raised,
                      color: Palette.shu),
                ),
              _header(),
              const SizedBox(height: 18),
              if (anime.genres.isNotEmpty) _genres(),
              const SizedBox(height: 18),
              Text(
                synopsis == null || synopsis.isEmpty
                    ? 'Pas encore de synopsis. Utilise « Corriger la fiche » pour retrouver la série.'
                    : synopsis,
                style: const TextStyle(
                    height: 1.55, fontSize: 14.5, color: Palette.text),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _working ? null : _translate,
                    icon: const Icon(Icons.translate, size: 18),
                    label: const Text('Traduire'),
                  ),
                  if (anime.synopsisTranslated != null)
                    TextButton(
                      onPressed: () =>
                          setState(() => _showOriginal = !_showOriginal),
                      child: Text(
                        _showOriginal ? 'Voir la traduction' : 'Voir l\'original',
                        style: const TextStyle(color: Palette.kin),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _searchAgain,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Corriger la fiche'),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(width: 3, height: 16, color: Palette.shu),
                      const SizedBox(width: 8),
                      Text(
                        'Épisodes (${anime.episodes.length})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (anime.episodes.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _play(0),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Tout lire'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < anime.episodes.length; i++)
                _episodeTile(i, anime.episodes[i]),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    final info = [
      if (anime.year != null) '${anime.year}',
      if (anime.type != null) anime.type!,
      if (anime.episodesCount != null) '${anime.episodesCount} episodes',
      if (anime.status != null) anime.status!,
      if (anime.studios != null) anime.studios!,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(radiusSm),
          child: SizedBox(
            width: 128,
            height: 186,
            child: anime.imageUrl == null
                ? Container(
                    color: Palette.raised,
                    child: const Icon(Icons.movie_outlined,
                        color: Palette.muted, size: 32),
                  )
                : CachedNetworkImage(
                    imageUrl: anime.imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Palette.raised),
                    errorWidget: (_, __, ___) =>
                        Container(color: Palette.raised),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                anime.title,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (anime.nativeTitle != null && anime.nativeTitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    anime.nativeTitle!,
                    style: const TextStyle(
                        color: Palette.muted, fontSize: 12.5, height: 1.3),
                  ),
                ),
              const SizedBox(height: 6),
              if (anime.score != null)
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 18, color: Palette.kin),
                    const SizedBox(width: 4),
                    Text(
                      anime.score!.toStringAsFixed(2),
                      style: const TextStyle(
                          color: Palette.kin, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                info.join(' · '),
                style: const TextStyle(color: Palette.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Text(
                'Dossier : ${anime.id}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Palette.muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _genres() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: anime.genres
          .map((g) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x73D6B86A)),
                  borderRadius: BorderRadius.circular(radiusSm),
                ),
                child: Text(g,
                    style: const TextStyle(color: Palette.kin, fontSize: 12)),
              ))
          .toList(),
    );
  }

  Widget _episodeTile(int index, Episode e) {
    final missing = !library.episodeExists(e);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Palette.raised,
        child: Text('${index + 1}',
            style: const TextStyle(fontSize: 12, color: Palette.text)),
      ),
      title: Text(
        e.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          color: missing ? Palette.muted : Palette.text,
        ),
      ),
      subtitle: missing
          ? const Text('Fichier introuvable',
              style: TextStyle(fontSize: 11.5, color: Palette.shu))
          : null,
      trailing: const Icon(Icons.play_circle_outline, color: Palette.muted),
      onTap: missing ? null : () => _play(index),
    );
  }
}
