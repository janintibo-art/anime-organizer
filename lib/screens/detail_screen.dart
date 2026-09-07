import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/anime.dart';
import '../models/anime_meta.dart';
import '../services/library_controller.dart';
import '../services/metadata_service.dart';
import '../widgets/poster_image.dart';
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
            subtitle: Text(r.summaryLine,
                style: const TextStyle(color: Palette.muted, fontSize: 12)),
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

  Future<void> _askAi() async {
    setState(() => _working = true);
    final message = await library.identifyWithAi(anime);
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Les trois écritures du titre, quand elles sont connues.
  Widget _titleVariants() {
    final rows = <List<String>>[
      if (anime.romajiTitle != null && anime.romajiTitle!.isNotEmpty)
        ['Romaji', anime.romajiTitle!],
      if (anime.apiTitle != null && anime.apiTitle!.isNotEmpty)
        ['Anglais', anime.apiTitle!],
      if (anime.frenchTitle != null && anime.frenchTitle!.isNotEmpty)
        ['Français', anime.frenchTitle!],
      if (anime.nativeTitle != null && anime.nativeTitle!.isNotEmpty)
        ['日本語', anime.nativeTitle!],
    ];
    if (rows.length < 2) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 68,
                    child: Text(row[0],
                        style: const TextStyle(
                            color: Palette.muted, fontSize: 11.5)),
                  ),
                  Expanded(
                    child: Text(row[1],
                        style: const TextStyle(
                            fontSize: 13, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _play(int index, {Duration at = Duration.zero}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          title: anime.title,
          episodes: anime.episodes,
          startIndex: index,
          anime: anime,
          startAt: at,
        ),
      ),
    );
  }

  /// Regroupe les episodes par saison, les bonus a part.
  Map<String, List<int>> _bySeason() {
    final groups = <String, List<int>>{};
    final multiSeason = anime.seasons.length > 1;

    for (var i = 0; i < anime.episodes.length; i++) {
      final e = anime.episodes[i];
      final label = e.bonus
          ? 'Bonus et hors-série'
          : (multiSeason ? 'Saison ${e.season ?? 1}' : 'Épisodes');
      groups.putIfAbsent(label, () => []).add(i);
    }
    return groups;
  }

  /// Petit bilan : trous dans la numérotation, doublons, contenus bonus.
  Widget _healthCard() {
    final issues = anime.issues;
    if (issues.isEmpty) return const SizedBox.shrink();

    final lines = <String>[];
    issues.missing.forEach((season, holes) {
      final where = anime.seasons.length > 1 ? 'saison $season : ' : '';
      final list = holes.take(12).join(', ');
      lines.add('Épisodes manquants — $where$list'
          '${holes.length > 12 ? '…' : ''}');
    });
    issues.duplicates.forEach((season, doubled) {
      final where = anime.seasons.length > 1 ? 'saison $season : ' : '';
      lines.add('En double — $where${doubled.join(', ')}');
    });
    if (issues.bonusCount > 0) {
      lines.add(
          '${issues.bonusCount} fichier${issues.bonusCount > 1 ? 's' : ''} bonus '
          '(OAV, génériques, making-of)');
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.fact_check_outlined, size: 16, color: Palette.kin),
              SizedBox(width: 8),
              Text('État de la collection',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line,
                  style: const TextStyle(
                      color: Palette.muted, fontSize: 12, height: 1.4)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final synopsis = _showOriginal ? anime.synopsisEn : anime.synopsis;
        final seasons = _bySeason();

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              _banner(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_working)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Palette.raised,
                              color: Palette.shu),
                        ),
                      _resumeButton(),
                      const SizedBox(height: 16),
                      _badges(),
                      if (anime.genres.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _genres(),
                      ],
                      _titleVariants(),
                      _healthCard(),
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
                                _showOriginal
                                    ? 'Voir la traduction'
                                    : 'Voir l\'original',
                                style: const TextStyle(color: Palette.kin),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: _working ? null : _searchAgain,
                            icon: const Icon(Icons.search, size: 18),
                            label: const Text('Corriger la fiche'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _working ? null : _askAi,
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Identifier avec l\'IA'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                  width: 3, height: 16, color: Palette.shu),
                              const SizedBox(width: 8),
                              Text(
                                '${anime.episodes.length} épisodes',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => library.markAllWatched(
                                anime, !anime.finished),
                            child: Text(
                              anime.finished
                                  ? 'Tout marquer non vu'
                                  : 'Tout marquer vu',
                              style: const TextStyle(
                                  color: Palette.muted, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              for (final entry in seasons.entries) ...[
                if (seasons.length > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                            color: Palette.kin,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _episodeTile(entry.value[i]),
                      childCount: entry.value.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- bandeau

  Widget _banner() {
    return SliverAppBar(
      expandedHeight: 268,
      pinned: true,
      backgroundColor: Palette.ink,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Palette.text,
      actions: [
        IconButton(
          onPressed: () => library.toggleFavorite(anime),
          icon: Icon(
            anime.favorite ? Icons.favorite : Icons.favorite_border,
            color: anime.favorite ? Palette.sakura : Palette.text,
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 14),
        title: Text(
          anime.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            PosterImage(
              anime: anime,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            // L'affiche sert de decor : on l'assombrit pour garder le texte lisible.
            Container(color: const Color(0x99000000)),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Palette.ink, Color(0x000D0B0B)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 52,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (anime.nativeTitle != null &&
                      anime.nativeTitle!.trim().isNotEmpty)
                    Text(
                      anime.nativeTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Palette.muted, fontSize: 12.5),
                    ),
                  if (anime.progress > 0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: anime.progress,
                        minHeight: 4,
                        backgroundColor: const Color(0x55FFFFFF),
                        color: anime.finished ? Palette.kin : Palette.shu,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${anime.watchedCount} sur ${anime.episodes.length} épisodes vus',
                      style: const TextStyle(
                          color: Palette.muted, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumeButton() {
    if (anime.episodes.isEmpty) return const SizedBox.shrink();
    final index = anime.resumeIndex;
    final at = anime.resumePosition;
    final label = anime.finished
        ? 'Revoir depuis le début'
        : (at > Duration.zero
            ? 'Reprendre l\'épisode ${index + 1}'
            : (anime.started
                ? 'Lire l\'épisode ${index + 1}'
                : 'Lire le premier épisode'));

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Palette.shu,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
        onPressed: () => anime.finished ? _play(0) : _play(index, at: at),
        icon: const Icon(Icons.play_arrow),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _badges() {
    final items = <List<String>>[
      if (anime.year != null) ['Année', '${anime.year}'],
      if (anime.type != null) ['Format', anime.type!],
      if (anime.score != null) ['Note', anime.score!.toStringAsFixed(2)],
      if (anime.status != null) ['Statut', anime.status!],
      if (anime.studios != null) ['Studio', anime.studios!],
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Palette.surface,
              border: Border.all(color: Palette.line),
              borderRadius: BorderRadius.circular(radiusSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item[0],
                    style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 9.5,
                        letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(item[1],
                    style: TextStyle(
                        color: item[0] == 'Note' ? Palette.kin : Palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
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

  Widget _episodeTile(int index) {
    final e = anime.episodes[index];
    final missing = !library.episodeExists(e);
    final seen = anime.isWatched(e);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: GestureDetector(
        onTap: () => library.setWatched(anime, e, !seen),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: seen ? Palette.kin : Colors.transparent,
            border: Border.all(color: seen ? Palette.kin : Palette.line),
            shape: BoxShape.circle,
          ),
          child: seen
              ? const Icon(Icons.check, size: 16, color: Palette.ink)
              : Text(
                  e.bonus ? '★' : '${e.number ?? index + 1}',
                  style:
                      const TextStyle(fontSize: 12, color: Palette.muted)),
        ),
      ),
      title: Text(
        e.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          color: missing || seen ? Palette.muted : Palette.text,
        ),
      ),
      subtitle: missing
          ? const Text('Fichier introuvable',
              style: TextStyle(fontSize: 11.5, color: Palette.shu))
          : Text(e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Palette.muted)),
      trailing: const Icon(Icons.play_circle_outline, color: Palette.muted),
      onTap: missing ? null : () => _play(index),
    );
  }
}
