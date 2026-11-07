import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../models/anime.dart';
import 'player_screen.dart';

/// Remote videos are streamed (HTTP Range), never copied to the phone.
/// Credentials are sent in headers only; video URLs use expiring HMAC tickets.
class RemoteEpisodesScreen extends StatefulWidget {
  final String host;
  final String pairCode;
  final int seriesId;
  final String seriesTitle;

  const RemoteEpisodesScreen({super.key, required this.host,
    required this.pairCode, required this.seriesId, required this.seriesTitle});

  @override
  State<RemoteEpisodesScreen> createState() => _RemoteEpisodesScreenState();
}

class _RemoteEpisodesScreenState extends State<RemoteEpisodesScreen> {
  bool _busy = true;
  String? _error;
  List<Map<String, dynamic>> _episodes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Uri _endpoint(String path, Map<String, String> params) =>
    Uri.http('${widget.host}:8765', path, params);

  Future<void> _load() async {
    try {
      final r = await http.get(_endpoint('/v1/episodes',
          {'series': '${widget.seriesId}'}),
          headers: {'X-Anime-Pair-Code': widget.pairCode})
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      _episodes = (data['episodes'] as List? ?? [])
          .whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
    } catch (e) {
      _error = 'Épisodes indisponibles : $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(Map<String, dynamic> episode) async {
    final index = episode['id'];
    if (index is! int) return;
    setState(() => _busy = true);
    try {
      final r = await http.get(_endpoint('/v1/ticket',
          {'series': '${widget.seriesId}', 'episode': '$index'}),
          headers: {'X-Anime-Pair-Code': widget.pairCode})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('Vidéo indisponible (HTTP ${r.statusCode})');
      final ticket = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final path = ticket['path'];
      final expiry = ticket['expires'];
      final signature = ticket['signature'];
      if (path is! String || !path.startsWith('/v1/stream/') ||
          expiry is! int || signature is! String) {
        throw Exception('Ticket de lecture invalide');
      }
      final url = _endpoint(path, {
        'expires': '$expiry', 'signature': signature,
      }).toString();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(
        title: widget.seriesTitle,
        episodes: [Episode(path: url, name: '${episode['name'] ?? 'Épisode'}',
          season: episode['season'] as int?, number: episode['number'] as int?)],
      )));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Lecture impossible : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: darkAppBar(title: Text(widget.seriesTitle)),
    body: _busy && _episodes.isEmpty
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? Center(child: Text(_error!))
        : ListView.builder(
            itemCount: _episodes.length,
            itemBuilder: (context, i) {
              final e = _episodes[i];
              final available = e['available'] == true;
              final season = e['season'];
              final number = e['number'];
              return ListTile(
                leading: Icon(available ? Icons.play_circle_outline : Icons.block,
                  color: available ? Palette.kin : Palette.muted),
                title: Text('${e['name'] ?? 'Épisode'}'),
                subtitle: Text('Saison ${season ?? 1} · Épisode ${number ?? i + 1}'),
                onTap: !available || _busy ? null : () => _play(e),
              );
            }),
  );
}
