import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/anime.dart';

class AnimeCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  const AnimeCard({
    super.key,
    required this.anime,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _poster(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 56,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xCC0D0A14), Colors.transparent],
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
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xE60D0A14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          anime.score!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Palette.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
                      onPressed: onFavorite,
                      icon: Icon(
                        anime.favorite ? Icons.favorite : Icons.favorite_border,
                        color: anime.favorite ? Palette.sakura : Colors.white70,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 6,
                    child: Text(
                      '${anime.episodes.length} fichier${anime.episodes.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
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
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            anime.genres.isEmpty
                ? (anime.metaFetched ? 'Genre inconnu' : 'Fiche non chargee')
                : anime.genres.take(2).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: anime.genres.isEmpty ? Palette.muted : Palette.jade,
            ),
          ),
        ],
      ),
    );
  }

  Widget _poster() {
    if (anime.imageUrl == null || anime.imageUrl!.isEmpty) {
      return Container(
        color: Palette.raised,
        alignment: Alignment.center,
        child: const Icon(Icons.movie_outlined, color: Palette.muted, size: 34),
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
