import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/disk_history.dart';

/// Diagnostic non destructif : Windows Storage Reliability Counters.
/// Les valeurs SMART non disponibles restent inconnues (jamais 100 % inventé).
class DiskHealthScreen extends StatefulWidget {
  const DiskHealthScreen({super.key});

  @override
  State<DiskHealthScreen> createState() => _DiskHealthScreenState();
}

class _DiskHealthScreenState extends State<DiskHealthScreen> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _disks = const [];
  DateTime? _updated;
  final DiskHistory _history = DiskHistory();
  Timer? _monitorTimer;
  List<String> _alerts = const [];


  // Aucun contrôle ni écriture sur les disques : simple lecture des données Windows.
  // Une commande lancée sans shell, sans données issues des noms de disque.
  static const String _powershell = r'''
$ErrorActionPreference = 'Stop'
$items = @()
foreach ($disk in @(Get-PhysicalDisk -ErrorAction Stop)) {
  $r = $null
  try { $r = $disk | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
  $temperature = $null
  $wear = $null
  $hours = $null
  $uncorrectedRead = $null
  $uncorrectedWrite = $null
  if ($null -ne $r) {
    if ($null -ne $r.Temperature -and [int]$r.Temperature -gt 0) { $temperature = [int]$r.Temperature }
    if ($null -ne $r.Wear) { $wear = [int]$r.Wear }
    if ($null -ne $r.PowerOnHours) { $hours = [int64]$r.PowerOnHours }
    if ($null -ne $r.ReadErrorsUncorrected) { $uncorrectedRead = [int64]$r.ReadErrorsUncorrected }
    if ($null -ne $r.WriteErrorsUncorrected) { $uncorrectedWrite = [int64]$r.WriteErrorsUncorrected }
  }
  $items += [pscustomobject]@{
    name = [string]$disk.FriendlyName
    type = [string]$disk.MediaType
    health = [string]$disk.HealthStatus
    operational = [string]($disk.OperationalStatus -join ', ')
    size = [int64]$disk.Size
    temperature = $temperature
    wear = $wear
    powerOnHours = $hours
    readErrorsUncorrected = $uncorrectedRead
    writeErrorsUncorrected = $uncorrectedWrite
  }
}
ConvertTo-Json -InputObject @($items) -Depth 4 -Compress
''';

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _history.load();
        if (mounted) await _refresh();
      });
      // Actualisation tant que cet écran reste ouvert. Pas un service de fond.
      _monitorTimer = Timer.periodic(const Duration(minutes: 10), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || !Platform.isWindows) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', _powershell],
        runInShell: false,
      ).timeout(const Duration(seconds: 30));
      if (result.exitCode != 0) {
        throw StateError(result.stderr.toString().trim().isEmpty
            ? 'Windows n’a pas renvoyé les informations des disques.'
            : result.stderr.toString().trim());
      }
      final raw = jsonDecode(result.stdout.toString());
      final list = raw is List ? raw : (raw is Map ? [raw] : const []);
      final parsed = list
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
          .toList();
      if (!mounted) return;
      final now = DateTime.now();
      final alerts = _history.append(parsed, now);
      await _history.save();
      if (!mounted) return;
      setState(() {
        _disks = parsed;
        _updated = now;
        _alerts = alerts;
      });
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Le diagnostic Windows a dépassé 30 secondes.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Diagnostic indisponible : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _number(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  String _size(dynamic bytes) {
    final value = _number(bytes);
    if (value == null || value <= 0) return 'Capacité inconnue';
    if (value >= 1000000000000) return '${(value / 1000000000000).toStringAsFixed(2)} To';
    return '${(value / 1000000000).toStringAsFixed(0)} Go';
  }

  bool _isCritical(Map<String, dynamic> disk) {
    final state = (disk['health'] ?? '').toString().toLowerCase();
    return state.contains('unhealthy') || state.contains('failed');
  }

  bool _isWarning(Map<String, dynamic> disk) {
    final state = (disk['health'] ?? '').toString().toLowerCase();
    return state.contains('warning') ||
        (_number(disk['readErrorsUncorrected']) ?? 0) > 0 ||
        (_number(disk['writeErrorsUncorrected']) ?? 0) > 0;
  }

  Widget _diskCard(Map<String, dynamic> disk) {
    final critical = _isCritical(disk);
    final warning = _isWarning(disk);
    final health = (disk['health'] ?? 'Unknown').toString().toLowerCase();
    final status = critical
        ? 'Critique — sauvegarde immédiate conseillée'
        : warning
            ? 'À surveiller — vérifie ta sauvegarde'
            : health == 'healthy'
                ? 'Aucune alerte SMART déclarée'
                : 'État non déterminé';
    final color = critical ? const Color(0xFFF07171)
        : warning ? const Color(0xFFFFC45C)
        : health == 'healthy' ? const Color(0xFF76D7AC) : Palette.muted;
    final name = (disk['name'] ?? 'Disque sans nom').toString();
    final temp = _number(disk['temperature']);
    final wear = _number(disk['wear']);
    final isSsd = (disk['type'] ?? '').toString().toLowerCase().contains('ssd');
    final hours = _number(disk['powerOnHours']);
    final reads = _number(disk['readErrorsUncorrected']);
    final writes = _number(disk['writeErrorsUncorrected']);
    final historical = _history.forDisk(disk);
    final recentTemps = historical.reversed
        .map((e) => _number(e['temperature']))
        .whereType<int>()
        .take(24)
        .toList().reversed.toList();
    final wearHistory = historical.reversed
        .map((e) => _number(e['wear']))
        .whereType<int>()
        .take(24)
        .toList().reversed.toList();
    return Card(
      color: Palette.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.storage_outlined, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ]),
          const SizedBox(height: 5),
          Text('${disk['type'] ?? 'Type inconnu'} · ${_size(disk['size'])}',
              style: TextStyle(color: Palette.muted)),
          const SizedBox(height: 10),
          Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const Divider(height: 22),
          Wrap(spacing: 20, runSpacing: 12, children: [
            _metric('Température', temp == null ? 'Non disponible' : '$temp °C'),
            _metric('Usure SSD', !isSsd || wear == null ? 'Non disponible' : '${wear.clamp(0, 100)} %'),
            _metric('Heures de fonctionnement', hours == null ? 'Non disponible' : '$hours h'),
            _metric('Erreurs lecture non corrigées', reads == null ? 'Non disponible' : '$reads'),
            _metric('Erreurs écriture non corrigées', writes == null ? 'Non disponible' : '$writes'),
          ]),
          if (recentTemps.length > 1) ...[
            const SizedBox(height: 14),
            Text('Température · ${recentTemps.length} derniers relevés',
                style: TextStyle(color: Palette.muted, fontSize: 12)),
            const SizedBox(height: 5),
            SizedBox(height: 46, width: double.infinity,
                child: CustomPaint(painter: _TrendPainter(recentTemps))),
            Text('Min ${recentTemps.reduce((a, b) => a < b ? a : b)} °C · '
                'Max ${recentTemps.reduce((a, b) => a > b ? a : b)} °C',
                style: TextStyle(color: Palette.muted, fontSize: 12)),
          ],
          if (isSsd && wearHistory.length > 1)
            Padding(padding: const EdgeInsets.only(top: 8),
              child: Text('Usure SSD relevée : ${wearHistory.first} % → ${wearHistory.last} %',
                style: TextStyle(color: Palette.muted, fontSize: 12))),
        ]),
      ),
    );
  }

  Widget _metric(String title, String value) => SizedBox(
    width: 195,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: Palette.muted, fontSize: 12)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    ]),
  );

  Future<void> _copyReport() async {
    final lines = <String>['Anime Organizer — Rapport disques (${_updated ?? DateTime.now()})', ..._alerts];
    for (final d in _disks) {
      lines.add('${d['name']} | ${d['type']} | ${_size(d['size'])} | SMART ${d['health']} | '
          'temp ${d['temperature'] ?? 'N/D'} °C | usure ${d['wear'] ?? 'N/D'} % | '
          'heures ${d['powerOnHours'] ?? 'N/D'} | erreurs non corrigées '
          '${d['readErrorsUncorrected'] ?? 'N/D'}/${d['writeErrorsUncorrected'] ?? 'N/D'}');
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rapport copié.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: darkAppBar(title: const Text('État des disques'), actions: [
        if (Platform.isWindows)
          IconButton(tooltip: 'Actualiser le diagnostic',
              onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        if (_disks.isNotEmpty)
          IconButton(tooltip: 'Copier le rapport',
              onPressed: _copyReport, icon: const Icon(Icons.copy_outlined)),
      ]),
      body: !Platform.isWindows
          ? const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Le diagnostic SMART est disponible sur Windows. '
                  'Sur Android, les disques du PC ne peuvent pas être interrogés directement.',
                  textAlign: TextAlign.center)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('Surveillance des disques du PC',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('Lecture seule des données Windows. '
                  'Un état normal ne garantit pas qu’un disque ne tombera pas en panne.',
                  style: TextStyle(color: Palette.muted)),
              const SizedBox(height: 7),
              Text('Historique local sur 90 jours · relevé toutes les 10 minutes '
                  'tant que cet écran reste ouvert. La fermeture de l’application '
                  'arrête la surveillance.',
                  style: TextStyle(color: Palette.muted, fontSize: 12)),
              if (_history.storageError != null)
                Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text(_history.storageError!,
                    style: const TextStyle(color: Color(0xFFFFC45C)))),
              if (_alerts.isNotEmpty) Card(
                color: const Color(0xFF442D21),
                child: Padding(padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Alertes de surveillance',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    for (final item in _alerts)
                      Padding(padding: const EdgeInsets.only(top: 7), child: Text('• $item')),
                  ]))),
              if (_updated != null) Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text('Dernière analyse : ${_updated!.hour.toString().padLeft(2, '0')}:${_updated!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: Palette.muted, fontSize: 12)),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(_error!, style: const TextStyle(color: Color(0xFFFFC45C))),
              ),
              if (!_loading && _error == null && _disks.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Aucun disque détecté par Windows.')),
              const SizedBox(height: 12),
              for (final disk in _disks) _diskCard(disk),
              const SizedBox(height: 12),
              Text('Important : certains disques USB, boîtiers RAID ou contrôleurs '
                  'ne transmettent pas la température ou les données SMART. '
                  'L’usure n’est pas une probabilité de panne. Conserve au moins '
                  'une copie de ta bibliothèque sur un autre support.',
                  style: TextStyle(fontSize: 12, color: Palette.muted)),
            ]),
    );
  }
}


/// Petite courbe autonome : pas de bibliothèque graphique supplémentaire.
class _TrendPainter extends CustomPainter {
  final List<int> values;
  const _TrendPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final low = values.reduce((a, b) => a < b ? a : b).toDouble() - 2;
    final high = values.reduce((a, b) => a > b ? a : b).toDouble() + 2;
    final span = (high - low).clamp(1.0, double.infinity);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] - low) / span * size.height;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFFFC45C)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values.length != values.length ||
      !ListEqualityInt.same(oldDelegate.values, values);
}

class ListEqualityInt {
  static bool same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
    return true;
  }
}
