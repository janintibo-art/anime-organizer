import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../main.dart';
import '../models/anime.dart';
import '../services/library_controller.dart';
import '../services/poster_cache.dart';

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
  final FocusNode _focus = FocusNode();

  final List<StreamSubscription<dynamic>> _subs = [];
  int _index = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _seeked = false;
  double _rate = 1.0;
  Tracks? _tracks;
  Timer? _autoSave;
  bool _langApplied = false;
  String? _notice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex;

    // Plein écran automatique : le lecteur prend tout l'espace disponible.
    if (Platform.isAndroid) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

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
        _seeked = true;
        _langApplied = false;
      });
      _loadExternalSubtitle();
      if (library.settings.autoNext) {
        _flash('Épisode suivant');
      } else {
        _player.pause();
        _flash('Lecture en pause : enchaînement désactivé');
      }
    }));

    _subs.add(_player.stream.position.listen((p) => _position = p));

    _subs.add(_player.stream.duration.listen((d) {
      _duration = d;
      if (!_seeked && d.inSeconds > 0 && widget.startAt.inSeconds > 5) {
        _seeked = true;
        _player.seek(widget.startAt);
      }
    }));

    _subs.add(_player.stream.tracks.listen((t) {
      if (!mounted) return;
      setState(() => _tracks = t);
      _applyPreferredLanguages(t);
    }));

    _subs.add(_player.stream.completed.listen((done) {
      if (done) _persist(forceWatched: true);
    }));

    _autoSave = Timer.periodic(const Duration(seconds: 20), (_) => _persist());
    _loadExternalSubtitle();
  }

  void _flash(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// Charge le .srt ou .ass posé à côté de la vidéo, s'il y en a un.
  void _loadExternalSubtitle() {
    if (widget.episodes.isEmpty) return;
    final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    if (episode.subtitles.isEmpty) return;

    final preferred = library.settings.preferredSubtitle.toLowerCase();
    final chosen = episode.subtitles.firstWhere(
      (path) => preferred.isNotEmpty && path.toLowerCase().contains(preferred),
      orElse: () => episode.subtitles.first,
    );
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _player.setSubtitleTrack(SubtitleTrack.uri(Uri.file(chosen).toString()));
    });
  }

  /// Applique les langues préférées dès que les pistes sont connues.
  void _applyPreferredLanguages(Tracks tracks) {
    if (_langApplied) return;
    _langApplied = true;
    final audioPref = library.settings.preferredAudio.toLowerCase();
    final subPref = library.settings.preferredSubtitle.toLowerCase();

    if (audioPref.isNotEmpty) {
      for (final t in tracks.audio) {
        final lang = t.language ?? '';
        final title = t.title ?? '';
        final tag = '$lang $title'.toLowerCase();
        if (tag.contains(audioPref)) {
          _player.setAudioTrack(t);
          break;
        }
      }
    }
    if (subPref.isNotEmpty) {
      for (final t in tracks.subtitle) {
        final lang = t.language ?? '';
        final title = t.title ?? '';
        final tag = '$lang $title'.toLowerCase();
        if (tag.contains(subPref)) {
          _player.setSubtitleTrack(t);
          break;
        }
      }
    }
  }

  /// Capture l'image affichée et la garde comme affiche de la série.
  Future<void> _useFrameAsPoster() async {
    final anime = widget.anime;
    if (anime == null) return;
    final bytes = await _player.screenshot();
    if (bytes == null) {
      _flash('Capture impossible sur cette vidéo.');
      return;
    }
    final path = await PosterCache.saveBytes(anime.id, bytes);
    if (path == null) {
      _flash('Enregistrement impossible.');
      return;
    }
    anime.posterPath = path;
    await library.save();
    library.refresh();
    _flash('Affiche mise à jour.');
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
    _noticeTimer?.cancel();
    _persist();
    for (final s in _subs) {
      s.cancel();
    }
    _focus.dispose();
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ------------------------------------------------------------- commandes

  void _seekBy(int seconds) {
    final target = _position + Duration(seconds: seconds);
    _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  void _setRate(double rate) {
    setState(() => _rate = rate);
    _player.setRate(rate);
  }

  /// Raccourcis clavier, surtout utiles sous Windows.
  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _player.playOrPause();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
    } else if (key == LogicalKeyboardKey.keyS) {
      _seekBy(library.settings.skipIntroSeconds);
    } else if (key == LogicalKeyboardKey.keyN) {
      _player.next();
    } else if (key == LogicalKeyboardKey.keyP) {
      _player.previous();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _player.setVolume((_player.state.volume + 10).clamp(0, 100));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _player.setVolume((_player.state.volume - 10).clamp(0, 100));
    }
  }

  @override
  Widget build(BuildContext context) {
    final episode =
        widget.episodes[_index.clamp(0, widget.episodes.length - 1)];

    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            widget.episodes.isEmpty ? widget.title : episode.label,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Passer l\'intro',
              onPressed: () => _seekBy(library.settings.skipIntroSeconds),
              icon: const Icon(Icons.fast_forward),
            ),
            if (widget.anime != null)
              IconButton(
                tooltip: 'Utiliser cette image comme affiche',
                onPressed: _useFrameAsPoster,
                icon: const Icon(Icons.image_outlined),
              ),
            _rateMenu(),
            _trackMenu(),
            if (widget.episodes.length > 1)
              IconButton(
                tooltip: 'Épisode précédent (P)',
                onPressed: () => _player.previous(),
                icon: const Icon(Icons.skip_previous),
              ),
            if (widget.episodes.length > 1)
              IconButton(
                tooltip: 'Épisode suivant (N)',
                onPressed: () => _player.next(),
                icon: const Icon(Icons.skip_next),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Video(
                      controller: _controller,
                      controls: AdaptiveVideoControls,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (_notice != null)
                    Positioned(
                      left: 16,
                      top: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xE60D0B0B),
                          border: Border.all(color: Palette.shu),
                          borderRadius: BorderRadius.circular(radiusSm),
                        ),
                        child: Text(_notice!,
                            style: const TextStyle(
                                color: Palette.text, fontSize: 12.5)),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.episodes.length > 1) _episodeStrip(),
          ],
        ),
      ),
    );
  }

  Widget _rateMenu() {
    const rates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return PopupMenuButton<double>(
      color: Palette.surface,
      tooltip: 'Vitesse de lecture',
      onSelected: _setRate,
      itemBuilder: (_) => [
        for (final r in rates)
          PopupMenuItem(
            value: r,
            child: Row(
              children: [
                Icon(
                  r == _rate ? Icons.check : Icons.speed,
                  size: 16,
                  color: r == _rate ? Palette.shu : Palette.muted,
                ),
                const SizedBox(width: 10),
                Text('${r}x'),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Text(
            '${_rate}x',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
    );
  }

  String _trackLabel(dynamic track, String fallback) {
    final title = track.title as String?;
    final language = track.language as String?;
    if (title != null && title.isNotEmpty) {
      return language == null ? title : '$title ($language)';
    }
    if (language != null && language.isNotEmpty) return language;
    return fallback;
  }

  Widget _trackMenu() {
    final tracks = _tracks;
    if (tracks == null) return const SizedBox.shrink();

    final audio = tracks.audio.where((t) => t.id != 'auto').toList();
    final subs = tracks.subtitle.toList();

    return PopupMenuButton<void>(
      color: Palette.surface,
      tooltip: 'Pistes audio et sous-titres',
      icon: const Icon(Icons.subtitles_outlined),
      itemBuilder: (_) => [
        if (audio.isNotEmpty) ...[
          const PopupMenuItem(
            enabled: false,
            child: Text('Audio',
                style: TextStyle(color: Palette.muted, fontSize: 11.5)),
          ),
          for (final t in audio)
            PopupMenuItem(
              onTap: () => _player.setAudioTrack(t),
              child: Text(
                _trackLabel(t, 'Piste ${t.id}'),
                style: TextStyle(
                  color: _player.state.track.audio.id == t.id
                      ? Palette.shu
                      : Palette.text,
                  fontSize: 13,
                ),
              ),
            ),
        ],
        if (subs.isNotEmpty) ...[
          const PopupMenuItem(
            enabled: false,
            child: Text('Sous-titres',
                style: TextStyle(color: Palette.muted, fontSize: 11.5)),
          ),
          for (final t in subs)
            PopupMenuItem(
              onTap: () => _player.setSubtitleTrack(t),
              child: Text(
                t.id == 'no' ? 'Aucun' : _trackLabel(t, 'Piste ${t.id}'),
                style: TextStyle(
                  color: _player.state.track.subtitle.id == t.id
                      ? Palette.shu
                      : Palette.text,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _episodeStrip() {
    return SizedBox(
      height: 62,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.episodes.length,
        itemBuilder: (context, i) {
          final e = widget.episodes[i];
          final selected = i == _index;
          final seen = widget.anime?.isWatched(e) ?? false;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
                  e.bonus ? '★' : '${e.number ?? i + 1}',
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
    );
  }
}
