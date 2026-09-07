import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../main.dart';
import '../models/anime.dart';
import '../services/library_controller.dart';

class PlayerScreen extends StatefulWidget {
  final String title;
  final List<Episode> episodes;
  final int startIndex;
  final Anime? anime;
  final Duration startAt;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.episodes,
    this.startIndex = 0,
    this.anime,
    this.startAt = Duration.zero,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  final List<StreamSubscription<dynamic>> _subs = [];
  int _index = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _seeked = false;
  Timer? _autoSave;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex;

    _player.open(
      Playlist(
        widget.episodes.map((e) => Media(Uri.file(e.path).toString())).toList(),
        index: widget.startIndex,
      ),
    );

    _subs.add(_player.stream.playlist.listen((event) {
      if (!mounted || event.index == _index) return;
      _persist();
      setState(() {
        _index = event.index;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }));

    _subs.add(_player.stream.position.listen((p) => _position = p));

    _subs.add(_player.stream.duration.listen((d) {
      _duration = d;
      // La reprise ne peut se faire qu'une fois la duree connue.
      if (!_seeked && d.inSeconds > 0 && widget.startAt.inSeconds > 5) {
        _seeked = true;
        _player.seek(widget.startAt);
      }
    }));

    _subs.add(_player.stream.completed.listen((done) {
      if (done) _persist(forceWatched: true);
    }));

    // Sauvegarde reguliere : une fermeture brutale ne perd pas la position.
    _autoSave = Timer.periodic(const Duration(seconds: 20), (_) => _persist());
  }

  void _persist({bool forceWatched = false}) {
    final anime = widget.anime;
    if (anime == null || widget.episodes.isEmpty) return;
    final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    library.savePlayback(
      anime,
      episode,
      forceWatched ? _duration : _position,
      _duration,
    );
  }

  @override
  void dispose() {
    _autoSave?.cancel();
    _persist();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.episodes.isEmpty
        ? widget.title
        : widget.episodes[_index.clamp(0, widget.episodes.length - 1)].name;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(current, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.episodes.length > 1)
            IconButton(
              tooltip: 'Épisode précédent',
              onPressed: () => _player.previous(),
              icon: const Icon(Icons.skip_previous),
            ),
          if (widget.episodes.length > 1)
            IconButton(
              tooltip: 'Épisode suivant',
              onPressed: () => _player.next(),
              icon: const Icon(Icons.skip_next),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Video(
              controller: _controller,
              controls: AdaptiveVideoControls,
              fit: BoxFit.contain,
            ),
          ),
          if (widget.episodes.length > 1)
            SizedBox(
              height: 62,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.episodes.length,
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  final seen = widget.anime?.isWatched(widget.episodes[i]) ?? false;
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: GestureDetector(
                      onTap: () => _player.jump(i),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: selected ? Palette.shu : Colors.transparent,
                          border: Border.all(
                              color: selected
                                  ? Palette.shu
                                  : (seen ? Palette.kin : Palette.line)),
                          borderRadius: BorderRadius.circular(radiusSm),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : (seen ? Palette.kin : Palette.muted),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
