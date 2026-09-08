/// En-têtes communs à toutes les requêtes.
///
/// Le client HTTP de Dart s'annonce par défaut comme « Dart/3.x (dart:io) ».
/// Cloudflare, qui protège AniList, traite volontiers ce genre de signature
/// comme du trafic automatisé et répond 403. On se présente donc comme une
/// application identifiable, avec un contact, ce que demandent la plupart
/// des API publiques.
class AppHttp {
  static const String userAgent =
      'AnimeOrganizer/1.0 (application personnelle de bibliothèque; Flutter)';

  static Map<String, String> headers({
    String accept = 'application/json',
    bool json = false,
  }) {
    return {
      'User-Agent': userAgent,
      'Accept': accept,
      if (json) 'Content-Type': 'application/json',
    };
  }
}
