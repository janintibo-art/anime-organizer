import 'dart:convert';

import 'package:http/http.dart' as http;

/// Assistant IA branché sur une API compatible OpenAI (Groq, OpenRouter,
/// ou un serveur maison). Sert à identifier une série quand les bases de
/// données ne reconnaissent pas le nom du dossier, et à donner le titre
/// dans les trois écritures : romaji, anglais, français.
class AiService {
  static String baseUrl(String provider, String custom) {
    switch (provider) {
      case 'groq':
        return 'https://api.groq.com/openai/v1';
      case 'openrouter':
        return 'https://openrouter.ai/api/v1';
      default:
        final trimmed = custom.trim().replaceAll(RegExp(r'/+$'), '');
        return trimmed.isEmpty ? 'https://api.groq.com/openai/v1' : trimmed;
    }
  }

  static Map<String, String> _headers(String key) => {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      };

  /// Liste les modèles proposés par le fournisseur.
  static Future<List<String>> listModels({
    required String provider,
    required String apiKey,
    String custom = '',
  }) async {
    if (apiKey.trim().isEmpty) return const [];
    try {
      final res = await http
          .get(Uri.parse('${baseUrl(provider, custom)}/models'),
              headers: _headers(apiKey))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = body['data'] as List? ?? const [];
      final ids = data
          .map((e) => (e as Map)['id']?.toString())
          .whereType<String>()
          .toList()
        ..sort();
      return ids;
    } catch (_) {
      return const [];
    }
  }

  /// Envoie une question et renvoie la réponse brute, ou null en cas d'échec.
  static Future<String?> ask({
    required String provider,
    required String apiKey,
    required String model,
    required String system,
    required String user,
    String custom = '',
    int maxTokens = 400,
  }) async {
    if (apiKey.trim().isEmpty || model.trim().isEmpty) return null;
    try {
      final res = await http
          .post(
            Uri.parse('${baseUrl(provider, custom)}/chat/completions'),
            headers: _headers(apiKey),
            body: jsonEncode({
              'model': model,
              'temperature': 0.2,
              'max_tokens': maxTokens,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final choices = body['choices'] as List? ?? const [];
      if (choices.isEmpty) return null;
      return ((choices.first as Map)['message'] as Map?)?['content']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Vérifie que la clé et le modèle répondent.
  static Future<String> test({
    required String provider,
    required String apiKey,
    required String model,
    String custom = '',
  }) async {
    if (apiKey.trim().isEmpty) return 'Aucune clé renseignée.';
    if (model.trim().isEmpty) return 'Aucun modèle choisi.';
    final answer = await ask(
      provider: provider,
      apiKey: apiKey,
      model: model,
      custom: custom,
      system: 'Réponds par un seul mot.',
      user: 'Dis simplement : ok',
      maxTokens: 10,
    );
    if (answer == null) {
      return 'Pas de réponse. Vérifie la clé, le modèle et la connexion.';
    }
    return 'Connexion réussie — réponse : ${answer.trim()}';
  }

  /// Identifie une série à partir d'un nom de dossier.
  static Future<AiTitles?> identify({
    required String folderTitle,
    required String provider,
    required String apiKey,
    required String model,
    String custom = '',
  }) async {
    const system =
        'Tu identifies des séries d\'animation japonaise à partir de noms de '
        'dossiers ou de fichiers, souvent mal orthographiés ou traduits. '
        'Tu réponds uniquement par un objet JSON, sans texte autour, sans '
        'balises de code.';

    final user = 'Nom trouvé sur le disque : "$folderTitle".\n'
        'Identifie la série et réponds avec ce JSON exactement :\n'
        '{"romaji":"","english":"","french":"","japanese":"","year":null,'
        '"confidence":0.0}\n'
        'romaji = titre en lettres latines tel qu\'utilisé au Japon, '
        'english = titre anglais officiel, french = titre français officiel '
        '(ou le titre anglais si aucun titre français n\'existe), '
        'japanese = titre en écriture japonaise. '
        'confidence entre 0 et 1. Si tu ne reconnais pas la série, '
        'mets des chaînes vides et confidence à 0.';

    final answer = await ask(
      provider: provider,
      apiKey: apiKey,
      model: model,
      custom: custom,
      system: system,
      user: user,
    );
    if (answer == null) return null;
    return AiTitles.parse(answer);
  }
}

class AiTitles {
  final String romaji;
  final String english;
  final String french;
  final String japanese;
  final int? year;
  final double confidence;

  const AiTitles({
    this.romaji = '',
    this.english = '',
    this.french = '',
    this.japanese = '',
    this.year,
    this.confidence = 0,
  });

  bool get usable =>
      confidence >= 0.3 && (romaji.isNotEmpty || english.isNotEmpty);

  /// Meilleure requête à envoyer aux bases de données.
  String get searchQuery => romaji.isNotEmpty ? romaji : english;

  /// Les modèles ajoutent parfois du texte ou des balises autour du JSON.
  static AiTitles? parse(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final map =
          jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
      return AiTitles(
        romaji: (map['romaji'] ?? '').toString().trim(),
        english: (map['english'] ?? '').toString().trim(),
        french: (map['french'] ?? '').toString().trim(),
        japanese: (map['japanese'] ?? '').toString().trim(),
        year: map['year'] is num ? (map['year'] as num).toInt() : null,
        confidence: map['confidence'] is num
            ? (map['confidence'] as num).toDouble()
            : 0,
      );
    } catch (_) {
      return null;
    }
  }
}
