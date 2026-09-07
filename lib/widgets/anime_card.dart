import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/anime.dart';

/// Affiche d'une serie. Reagit au survol sous Windows et a l'appui sur mobile.
class AnimeCard extends StatefulWidget {
  final Anime anime;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final double titleSize;

  const AnimeCard({
    super.key,
    required this.anime,
    required this.onTap,
    required this.onFavorite,
    this.titleSize = 13.5,
  });

  @override
  State<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<AnimeCard> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    final scale = _down ? 0.97 : (_hover ? 1.03 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radiusMd),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _poster(anime),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 62,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xE60D0B0B), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      if (anime.score != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Palette.shu,
                              borderRadius: BorderRadius.circular(radiusSm),
                            ),
                            child: Text(
                              anime.score!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onFavorite,
                          icon: Icon(
                            anime.favorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: anime.favorite
                                ? Palette.sakura
                                : Colors.white70,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: anime.progress > 0 ? 12 : 6,
                        child: Text(
                          anime.progress > 0
                              ? '${anime.watchedCount}/${anime.episodes.length} vus'
                              : '${anime.episodes.length} fichier${anime.episodes.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (anime.progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: anime.progress,
                            minHeight: 3,
                            backgroundColor: const Color(0x66000000),
                            color: anime.finished ? Palette.kin : Palette.shu,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.titleSize,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                anime.genres.isEmpty
                    ? (anime.metaFetched ? 'Genre inconnu' : 'Fiche non chargée')
                    : anime.genres.take(2).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: anime.genres.isEmpty ? Palette.muted : Palette.kin,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster(Anime anime) {
    if (anime.imageUrl == null || anime.imageUrl!.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Palette.surface,
          border: Border.all(color: Palette.line),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.movie_outlined, color: Palette.muted, size: 32),
      );
    }
    return CachedNetworkImage(
      imageUrl: anime.imageUrl!,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => Container(color: Palette.raised),
      errorWidget: (_, __, ___) => Container(
        color: Palette.raised,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: Palette.muted),
      ),
    );
  }
}

/// Ligne compacte pour le mode liste.
class AnimeRow extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const AnimeRow({super.key, required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(radiusSm),
              child: SizedBox(
                width: 46,
                height: 66,
                child: anime.imageUrl == null
                    ? Container(
                        color: Palette.raised,
                        child: const Icon(Icons.movie_outlined,
                            color: Palette.muted, size: 18),
                      )
                    : CachedNetworkImage(
                        imageUrl: anime.imageUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(anime.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (anime.year != null) '${anime.year}',
                      if (anime.genres.isNotEmpty) anime.genres.first,
                      '${anime.episodes.length} épisodes',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Palette.muted, fontSize: 11.5),
                  ),
                  if (anime.progress > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: anime.progress,
                        minHeight: 3,
                        backgroundColor: Palette.line,
                        color: anime.finished ? Palette.kin : Palette.shu,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (anime.score != null)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(anime.score!.toStringAsFixed(1),
                    style: const TextStyle(
                        color: Palette.kin,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}
