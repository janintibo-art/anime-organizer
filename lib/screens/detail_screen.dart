import 'dart:io';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/anime.dart';
import '../models/anime_meta.dart';
import '../services/library_controller.dart';
import '../services/backdrop_service.dart';
import '../services/metadata_service.dart';
import '../services/scanner.dart';
import '../widgets/poster_image.dart';
import 'genre_links.dart';
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
  bool _immersiveBackground = true;

  Anime get anime => widget.anime;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBackdrop());
  }

  Future<void> _loadBackdrop({bool force = false}) async {
    if (anime.backdropManual) return;
    if (!force && anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) return;
    final apiKey = library.settings.tmdbKey.trim();
    if (apiKey.isEmpty) {
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Renseigne ta clé TMDB dans les réglages pour chercher un panorama.'),
        ));
      }
      return;
    }
    if (force && mounted) setState(() => _working = true);
    try {
      final titles = <String>{
        if (anime.apiTitle != null) anime.apiTitle!,
        if (anime.romajiTitle != null) anime.romajiTitle!,
        anime.folderTitle,
      }.where((t) => t.trim().isNotEmpty);
      String? url;
      for (final title in titles) {
        url = await BackdropService.findBackdrop(title, apiKey);
        if (url != null) break;
      }
      if (!mounted) return;
      if (url != null) {
        anime.backdropUrl = url;
        await library.save();
        if (mounted) setState(() {});
      }
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          url == null ? 'Aucun panorama fiable trouvé : affiche conservée.' : 'Panorama actualisé.'
        )));
      }
    } finally {
      if (force && mounted) setState(() => _working = false);
    }
  }

  Future<void> _chooseBackdrop() async {
    final key = library.settings.tmdbKey.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Renseigne une clé TMDB dans les réglages pour choisir une image.'),
      ));
      return;
    }
    setState(() => _working = true);
    var candidates = <String>[];
    try {
      final titles = <String>{
        if (anime.apiTitle != null) anime.apiTitle!,
        if (anime.romajiTitle != null) anime.romajiTitle!,
        anime.folderTitle,
      };
      for (final title in titles.where((t) => t.trim().isNotEmpty)) {
        candidates = await BackdropService.findBackdrops(title, key);
        if (candidates.isNotEmpty) break;
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun panorama disponible pour cette série.'),
      ));
      return;
    }
    // null : annuler; chaine vide : repasser en mode automatique.
    final selection = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (ctx) => SafeArea(child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Expanded(child: Text('Choisir un panorama',
                style: TextStyle(color: Palette.text, fontSize: 19,
                    fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close)),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, ''),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Revenir au panorama automatique'),
            )),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth > 800 ? 3 : 2;
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns, childAspectRatio: 16 / 10,
                crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: candidates.length,
              itemBuilder: (_, i) {
                final url = candidates[i];
                return InkWell(onTap: () => Navigator.pop(ctx, url),
                  child: Stack(fit: StackFit.expand, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator()),
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image))),
                    if (anime.backdropUrl == url)
                      const Align(alignment: Alignment.topRight,
                        child: Padding(padding: EdgeInsets.all(8),
                          child: Icon(Icons.check_circle, color: Colors.white))),
                  ]),
                );
              },
            );
          })),
        ]),
      )),
    );
    if (selection == null || !mounted) return;
    if (selection.isEmpty) {
      anime.backdropManual = false;
      anime.backdropUrl = null;
    } else {
      anime.backdropManual = true;
      anime.backdropUrl = selection;
    }
    await library.save();
    if (mounted) setState(() {});
    if (selection.isEmpty) unawaited(_loadBackdrop());
  }

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
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(anime.synopsisEn == null
                ? 'Pas de synopsis à traduire.'
                : (library.lastTranslateError ??
                    'Traduction indisponible. Vérifie le fournisseur dans les réglages.')),
          ),
        );
      }
    }, 'La traduction a échoué.');
  }

  Future<void> _searchAgain() async {
    final suggested = Scanner.titleFromFiles(anime.episodes);
    final controller = TextEditingController(
        text: suggested ?? anime.folderTitle);
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
    // Si la catégorie a été mal détectée, la correction doit aussi
    // proposer les résultats occidentaux (TMDB + TVmaze).
    final western = anime.category == 'western' || anime.category == 'adult';
    final primary = await MetadataService.searchMany(
      query,
      source: western ? 'western' : library.settings.metaSource,
      tmdbKey: library.settings.tmdbKey,
    );
    final alternatives = western
        ? <AnimeMeta>[]
        : await MetadataService.searchMany(query, source: 'western',
            tmdbKey: library.settings.tmdbKey);
    final found = <AnimeMeta>[];
    final seen = <String>{};
    for (final result in [...primary, ...alternatives]) {
      final key = result.source + ':' + (result.sourceId?.toString() ?? result.title);
      if (seen.add(key)) found.add(result);
    }
    found.sort((a, b) => MetadataService.similarity(query, b.title)
        .compareTo(MetadataService.similarity(query, a.title)));
    final results = found.take(20).toList();
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
                ? Icon(Icons.movie_outlined, color: Palette.muted)
                : SizedBox(
                    width: 40,
                    child: CachedNetworkImage(
                        imageUrl: r.imageUrl!, fit: BoxFit.cover)),
            title: Text(r.title, style: const TextStyle(fontSize: 14)),
            subtitle: Text(r.summaryLine,
                style: TextStyle(color: Palette.muted, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, r),
          );
        },
      ),
    );
    if (chosen == null) return;

    await _run(() async {
      library.applyMeta(anime, chosen);
      library.manualIds.add(anime.id);
      library.remember(anime.folderTitle, chosen.titleRomaji ?? chosen.title);
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

  Future<void> _adjustBackdrop() async {
    var x = anime.backdropAlignX;
    var y = anime.backdropAlignY;
    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Cadrage du panorama'),
        content: SizedBox(width: 390, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (anime.backdropUrl != null)
              AspectRatio(aspectRatio: 16/9,
                child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: anime.backdropUrl!, fit: BoxFit.cover,
                    alignment: Alignment(x, y),
                  ))),
            const SizedBox(height: 12),
            const Text('Deplacer horizontalement'),
            Slider(value: x, min: -1, max: 1,
              onChanged: (v) => refresh(() => x = v)),
            const Text('Deplacer verticalement'),
            Slider(value: y, min: -1, max: 1,
              onChanged: (v) => refresh(() => y = v)),
          ],
        )),
        actions: [
          TextButton(onPressed: () => refresh(() {x=0; y=0;}),
            child: const Text('Centrer')),
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer')),
        ],
      )),
    );
    if (changed != true || !mounted) return;
    anime.backdropAlignX = x;
    anime.backdropAlignY = y;
    await library.save();
    if (mounted) setState(() {});
  }

  Widget _backgroundArt() {
    final path = anime.backdropUrl == null ? anime.posterPath : null;
    final remote = anime.backdropUrl ?? anime.imageUrl;
    final position = Alignment(anime.backdropAlignX, anime.backdropAlignY);
    Widget image;
    if (path != null && File(path).existsSync()) {
      image = Image.file(File(path), fit: BoxFit.cover,
          alignment: position,
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
    } else if (remote != null && remote.isNotEmpty) {
      image = CachedNetworkImage(imageUrl: remote, fit: BoxFit.cover,
          alignment: position,
          errorWidget: (_, __, ___) => const SizedBox.shrink());
    } else {
      image = const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        image,
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0x77000000), Palette.ink.withOpacity(0.62),
                   Palette.ink.withOpacity(0.88)],
          stops: const [0.0, 0.45, 1.0],
        ))),
      ]),
    );
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
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 3),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          collapsedBackgroundColor: Colors.transparent,
          backgroundColor: const Color(0x6611151C),
          iconColor: Palette.kin,
          collapsedIconColor: Palette.kin,
          title: Text('Titres et langues', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Palette.kin)),
          children: [for (final row in rows)
            Padding(padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 72, child: Text(row[0],
                      style: TextStyle(color: Palette.muted, fontSize: 12))),
                  Expanded(child: SelectableText(row[1],
                      style: const TextStyle(fontSize: 13, height: 1.35))),
                ])),
          ],
        ),
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
    final twins = library.duplicatesOf(anime);
    if (issues.isEmpty && twins.isEmpty) return const SizedBox.shrink();

    final lines = <String>[];
    for (final t in twins) {
      lines.add('Également présent dans ${t.id}');
    }
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
            children: [
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
                  style: TextStyle(
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
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_immersiveBackground) _backgroundArt(),
              ScrollConfiguration(
            behavior: const TextPageScrollBehavior(),
            child: CustomScrollView(
            slivers: [
              _banner(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_working)
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Palette.raised,
                              color: Palette.shu),
                        ),
                      _identityHeader(),
                      _resumeButton(),
                      const SizedBox(height: 16),
                      _badges(),
                      if (anime.genres.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _genres(),
                      ],
                      _titleVariants(),
                      const SizedBox(height: 18),
                      SelectableText(
                        synopsis == null || synopsis.isEmpty
                            ? 'Pas encore de synopsis. Utilise « Corriger la fiche » pour retrouver la série.'
                            : synopsis,
                        style: TextStyle(
                            height: 1.55, fontSize: 14.5, color: Palette.text),
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
                              style: TextStyle(
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
                        style: TextStyle(
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
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _detailMenuAction(String action) async {
    if (_working && !['health', 'titles', 'original', 'background'].contains(action)) {
      return;
    }
    switch (action) {
      case 'health':
        final issues = anime.issues;
        final twins = library.duplicatesOf(anime);
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          backgroundColor: Palette.surface,
          title: const Text('Etat de la collection'),
          content: SizedBox(
            width: 570,
            child: SingleChildScrollView(child:
              issues.isEmpty && twins.isEmpty
                ? const Text('Aucune anomalie detectee dans cette collection.')
                : _healthCard()),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'))],
        ));
        break;
      case 'titles':
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          backgroundColor: Palette.surface,
          title: const Text('Titres et langues'),
          content: SingleChildScrollView(child: SizedBox(
            width: 540, child: _titleVariants())),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'))],
        ));
        break;
      case 'translate': await _translate(); break;
      case 'original': setState(() => _showOriginal = !_showOriginal); break;
      case 'background':
        setState(() => _immersiveBackground = !_immersiveBackground); break;
      case 'refresh': await _loadBackdrop(force: true); break;
      case 'choose': await _chooseBackdrop(); break;
      case 'crop':
        if (anime.backdropUrl != null) await _adjustBackdrop();
        break;
      case 'correct': await _searchAgain(); break;
      case 'ai': await _askAi(); break;
      case 'category':
        if (!mounted) return;
        final chosen = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Palette.surface,
          builder: (ctx) => SafeArea(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              ListTile(title: const Text('Anime japonais'),
                onTap: () => Navigator.pop(ctx, 'anime')),
              ListTile(title: const Text('Dessin anime'),
                onTap: () => Navigator.pop(ctx, 'western')),
              ListTile(title: const Text('Animation adulte'),
                onTap: () => Navigator.pop(ctx, 'adult')),
              ListTile(title: const Text('Autre animation'),
                onTap: () => Navigator.pop(ctx, 'other')),
            ],
          )),
        );
        if (chosen != null) {
          anime.category = chosen;
          await library.save();
          library.refresh();
        }
        break;
    }
  }

  // ---------------------------------------------------------------- bandeau

  // V20_IMMERSIVE : le panorama unique est celui du fond de la fiche.
  Widget _banner() {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 54,
      backgroundColor: Palette.ink.withOpacity(0.66),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      title: Text(anime.title, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      actions: [
        // V21_MENU_IMMERSIF: les reglages occasionnels quittent le panorama.
        PopupMenuButton<String>(
          tooltip: 'Informations et options de la fiche',
          icon: const Icon(Icons.more_vert),
          onSelected: _detailMenuAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'health', child: ListTile(
              dense: true, leading: Icon(Icons.fact_check_outlined),
              title: Text('Etat de la collection'))),
            PopupMenuItem(value: 'titles', child: ListTile(
              dense: true, leading: Icon(Icons.translate_outlined),
              title: Text('Titres et langues'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'translate', child: ListTile(
              dense: true, leading: Icon(Icons.translate),
              title: Text('Traduire la description'))),
            PopupMenuItem(value: 'original', child: ListTile(
              dense: true, leading: Icon(Icons.menu_book_outlined),
              title: Text('Voir original / traduction'))),
            PopupMenuItem(value: 'background', child: ListTile(
              dense: true, leading: Icon(Icons.wallpaper_outlined),
              title: Text('Changer le mode de fond'))),
            PopupMenuItem(value: 'refresh', child: ListTile(
              dense: true, leading: Icon(Icons.landscape_outlined),
              title: Text('Actualiser le panorama'))),
            PopupMenuItem(value: 'choose', child: ListTile(
              dense: true, leading: Icon(Icons.collections_outlined),
              title: Text('Choisir le panorama'))),
            PopupMenuItem(value: 'crop', child: ListTile(
              dense: true, leading: Icon(Icons.crop_free),
              title: Text('Ajuster le cadrage'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'category', child: ListTile(
              dense: true, leading: Icon(Icons.category_outlined),
              title: Text('Changer la categorie'))),
            PopupMenuItem(value: 'correct', child: ListTile(
              dense: true, leading: Icon(Icons.search),
              title: Text('Corriger la fiche'))),
            PopupMenuItem(value: 'ai', child: ListTile(
              dense: true, leading: Icon(Icons.auto_awesome),
              title: Text('Identifier avec l IA'))),
          ],
        ),
        IconButton(
          tooltip: 'Favori',
          onPressed: () => library.toggleFavorite(anime),
          icon: Icon(anime.favorite ? Icons.favorite : Icons.favorite_border,
              color: anime.favorite ? Palette.sakura : Colors.white),
        ),
      ],
    );
  }

  Widget _identityHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusMd),
            child: SizedBox(width: 82, height: 116,
                child: PosterImage(anime: anime, iconSize: 24)),
          ),
          const SizedBox(width: 15),
          Expanded(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(anime.title, maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 25,
                    height: 1.12, fontWeight: FontWeight.w700)),
              if (anime.nativeTitle != null &&
                  anime.nativeTitle!.trim().isNotEmpty &&
                  anime.nativeTitle != anime.title) ...[
                const SizedBox(height: 5),
                Text(anime.nativeTitle!, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Palette.muted, fontSize: 12)),
              ],
              if (anime.progress > 0) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: anime.progress, minHeight: 3,
                  backgroundColor: const Color(0x55FFFFFF), color: Palette.kin),
                const SizedBox(height: 4),
                Text('${anime.watchedCount} / ${anime.episodes.length} épisodes vus',
                    style: TextStyle(color: Palette.muted, fontSize: 11)),
              ],
            ],
          )),
        ],
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
            ? "Reprendre l'épisode ${index + 1}"
            : "Lire l'épisode ${index + 1}");
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => anime.finished ? _play(0) : _play(index, at: at),
        icon: Icon(Icons.play_arrow_rounded, color: Palette.kin, size: 22),
        label: Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xB51A1C24),
          side: const BorderSide(color: Color(0xAAE5AF6D)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
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
              color: const Color(0x99171D25),
              border: Border.all(color: const Color(0x50FFFFFF)),
              borderRadius: BorderRadius.circular(radiusSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item[0],
                    style: TextStyle(
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
          .map((g) => Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openGenre(g),
                  borderRadius: BorderRadius.circular(radiusSm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x73D6B86A)),
                      borderRadius: BorderRadius.circular(radiusSm),
                    ),
                    child: Text(g,
                        style: TextStyle(color: Palette.kin, fontSize: 12)),
                  ),
                ),
              ))
          .toList(),
    );
  }

  /// Un genre touché : les autres séries de la bibliothèque qui le
  /// portent, et un accès au catalogue filtré dessus.
  void _openGenre(String genre) {
    final others = library.animes
        .where((o) => o.id != anime.id && o.genres.contains(genre))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheet).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(genre,
                    style: TextStyle(
                        color: Palette.kin,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  others.isEmpty
                      ? 'Aucune autre série de ta bibliothèque ne porte ce genre.'
                      : '${others.length} autre(s) dans ta bibliothèque',
                  style: TextStyle(color: Palette.muted, fontSize: 12.5),
                ),
              ),
              if (others.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: others.length,
                    itemBuilder: (_, i) {
                      final o = others[i];
                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(radiusSm),
                          child: SizedBox(
                            width: 38,
                            height: 54,
                            child: PosterImage(anime: o, iconSize: 18),
                          ),
                        ),
                        title: Text(o.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: o.year == null
                            ? null
                            : Text('${o.year}',
                                style: TextStyle(
                                    color: Palette.muted, fontSize: 12)),
                        onTap: () {
                          Navigator.of(sheet).pop();
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => DetailScreen(anime: o)));
                        },
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.travel_explore, size: 18),
                  label: const Text('Voir ce genre dans le catalogue'),
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    GenreLinks.open(context, genre);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
              ? Icon(Icons.check, size: 16, color: Palette.ink)
              : Text(
                  e.bonus ? '★' : '${e.number ?? index + 1}',
                  style:
                      TextStyle(fontSize: 12, color: Palette.muted)),
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
          ? Text('Fichier introuvable',
              style: TextStyle(fontSize: 11.5, color: Palette.shu))
          : Row(
              children: [
                if (anime.episodeHasVf(e)) ...[
                  Text('VF',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Palette.kin)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Palette.muted)),
                ),
              ],
            ),
      trailing: Icon(Icons.play_circle_outline, color: Palette.muted),
      onTap: missing ? null : () => _play(index),
    );
  }
}
