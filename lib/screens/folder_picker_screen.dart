import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../main.dart';

/// Explorateur de dossiers maison.
/// Ecrit avec dart:io uniquement : pas de plugin natif, donc le meme
/// comportement sur Windows et sur Android, et rien a maintenir cote Gradle.
class FolderPickerScreen extends StatefulWidget {
  final String? initialPath;
  const FolderPickerScreen({super.key, this.initialPath});

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  String? _current;
  List<Directory> _children = [];
  List<_Root> _roots = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _roots = _listRoots();
    final start = widget.initialPath;
    if (start != null && Directory(start).existsSync()) {
      _open(start);
    } else if (_roots.length == 1) {
      _open(_roots.first.path);
    }
  }

  /// Points de depart proposes selon la plateforme.
  List<_Root> _listRoots() {
    final roots = <_Root>[];
    if (Platform.isAndroid) {
      for (final candidate in const [
        ['/storage/emulated/0', 'Memoire interne'],
        ['/storage/emulated/0/Download', 'Telechargements'],
        ['/storage/emulated/0/Movies', 'Videos'],
        ['/storage/emulated/0/DCIM', 'DCIM'],
      ]) {
        if (Directory(candidate[0]).existsSync()) {
          roots.add(_Root(candidate[0], candidate[1]));
        }
      }
      // Cartes SD et cles USB montees sous /storage
      try {
        for (final e in Directory('/storage').listSync()) {
          if (e is! Directory) continue;
          final name = p.basename(e.path);
          if (name == 'emulated' || name == 'self') continue;
          if (_canList(e.path)) roots.add(_Root(e.path, 'Carte $name'));
        }
      } catch (_) {}
    } else if (Platform.isWindows) {
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final drive = '${String.fromCharCode(c)}:\\';
        if (Directory(drive).existsSync()) {
          roots.add(_Root(drive, 'Disque ${String.fromCharCode(c)}'));
        }
      }
    } else {
      roots.add(_Root('/', 'Racine'));
      final home = Platform.environment['HOME'];
      if (home != null && Directory(home).existsSync()) {
        roots.add(_Root(home, 'Dossier personnel'));
      }
    }
    return roots;
  }

  bool _canList(String path) {
    try {
      Directory(path).listSync().take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _open(String path) {
    try {
      final dirs = Directory(path)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('.'))
          .toList()
        ..sort((a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()));
      setState(() {
        _current = path;
        _children = dirs;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _current = path;
        _children = [];
        _error = 'Dossier illisible. Verifie les autorisations de stockage.';
      });
    }
  }

  void _goUp() {
    final current = _current;
    if (current == null) return;
    final parent = p.dirname(current);
    if (parent == current) {
      setState(() => _current = null);
    } else if (Directory(parent).existsSync()) {
      _open(parent);
    } else {
      setState(() => _current = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;

    return Scaffold(
      appBar: darkAppBar(
        title: Text(
          current == null ? 'Choisir un emplacement' : p.basename(current),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (current != null)
            IconButton(
              tooltip: 'Dossier parent',
              onPressed: _goUp,
              icon: const Icon(Icons.arrow_upward),
            ),
        ],
      ),
      floatingActionButton: current == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, current),
              backgroundColor: Palette.sakura,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.check),
              label: const Text('Choisir ce dossier'),
            ),
      body: current == null ? _rootList() : _folderList(current),
    );
  }

  Widget _rootList() {
    if (_roots.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aucun emplacement accessible. Accorde l\'acces au stockage puis reviens ici.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final r in _roots)
          ListTile(
            leading: const Icon(Icons.storage, color: Palette.jade),
            title: Text(r.label),
            subtitle: Text(r.path,
                style: const TextStyle(color: Palette.muted, fontSize: 11.5)),
            onTap: () => _open(r.path),
          ),
      ],
    );
  }

  Widget _folderList(String current) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            current,
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_error!,
                style: const TextStyle(color: Palette.sakura, fontSize: 13)),
          ),
        Expanded(
          child: _children.isEmpty
              ? const Center(
                  child: Text('Aucun sous-dossier ici.',
                      style: TextStyle(color: Palette.muted)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: _children.length,
                  itemBuilder: (context, i) {
                    final d = _children[i];
                    return ListTile(
                      leading:
                          const Icon(Icons.folder_outlined, color: Palette.jade),
                      title: Text(p.basename(d.path),
                          style: const TextStyle(fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right,
                          color: Palette.muted, size: 20),
                      onTap: () => _open(d.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Root {
  final String path;
  final String label;
  const _Root(this.path, this.label);
}
