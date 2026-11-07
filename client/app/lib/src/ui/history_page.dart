import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';
import 'package:url_launcher/url_launcher.dart';

String formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String formatSize(int bytes) => bytes >= 1 << 20
    ? '${(bytes / (1 << 20)).toStringAsFixed(bytes % (1 << 20) == 0 ? 0 : 1)} Mio'
    : bytes >= 1024
    ? '${(bytes / 1024).toStringAsFixed(bytes % 1024 == 0 ? 0 : 1)} Kio'
    : '$bytes o';

/// Read-only history of a game; restoring is done on the web interface.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.api, required this.gameId, required this.title});
  final RomSyncApi api;
  final String gameId;
  final String title;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _versions = <RemoteVersion>[];
  int? _next;
  bool _loading = true;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await widget.api.versions(widget.gameId, before: _next);
      setState(() {
        _versions.addAll(page.versions);
        _next = page.nextBefore;
        _done = page.nextBefore == null;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.status == 404 ? 'Ce jeu n’a pas encore de save sur le serveur.' : e.message);
    } on ServerUnreachableException {
      setState(() => _error = 'Serveur injoignable.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sizeEvent(SizeEvent e, int size) => switch (e.type) {
    'trimmed' => 'reçue en ${formatSize(e.from)}, remplissage coupé',
    'shrunk' => 'taille du jeu passée de ${formatSize(e.from)} à ${formatSize(size)}',
    _ => 'taille forcée (avant : ${formatSize(e.from)})',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Historique — ${widget.title}'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Restaurer sur le site'),
            onPressed: () => launchUrl(widget.api.webGameUrl(widget.gameId)),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Lecture seule : pour restaurer une ancienne version, ouvre le jeu sur le site. '
                    'L’appli la téléchargera avant la prochaine partie.',
                  ),
                ),
                for (final v in _versions)
                  ListTile(
                    leading: Icon(
                      v.isActive ? Icons.star : Icons.history,
                      color: v.isActive ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(formatDate(v.savedAt)),
                    subtitle: Text(
                      [
                        v.deviceName ?? 'site web',
                        if (v.emulator.isNotEmpty) v.emulator,
                        formatSize(v.size),
                        if (v.isActive) 'active',
                        if (v.conflict) 'divergente',
                        if (v.pinned) 'épinglée',
                        if (v.savedAtReported != null) 'horloge corrigée',
                        if (v.sizeEvent != null) _sizeEvent(v.sizeEvent!, v.size),
                        if (v.note.isNotEmpty) '« ${v.note} »',
                      ].join(' · '),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_loading && !_done)
                  Center(
                    child: TextButton(onPressed: _load, child: const Text('Versions plus anciennes')),
                  ),
              ],
            ),
    );
  }
}
