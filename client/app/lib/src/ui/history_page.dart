import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';

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

  /// Builds the error in the current language.
  String Function(AppLocalizations)? _error;

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
      setState(() => _error = (l) => e.status == 404 ? l.historyNoSave : e.message);
    } on ServerUnreachableException {
      setState(() => _error = (l) => l.serverUnreachable);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sizeEvent(AppLocalizations l, SizeEvent e, int size) => switch (e.type) {
    'trimmed' => l.sizeTrimmed(formatSize(l, e.from)),
    'shrunk' => l.sizeShrunk(formatSize(l, e.from), formatSize(l, size)),
    _ => l.sizeForced(formatSize(l, e.from)),
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.historyTitle(widget.title)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.open_in_browser),
            label: Text(l.historyRestoreOnSite),
            onPressed: () => launchUrl(widget.api.webGameUrl(widget.gameId)),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!(l)))
          : ListView(
              children: [
                Padding(padding: const EdgeInsets.all(16), child: Text(l.historyReadOnly)),
                for (final v in _versions)
                  ListTile(
                    leading: Icon(
                      v.isActive ? Icons.star : Icons.history,
                      color: v.isActive ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(formatDate(l, v.savedAt)),
                    subtitle: Text(
                      [
                        v.deviceName ?? l.website,
                        if (v.emulator.isNotEmpty) v.emulator,
                        formatSize(l, v.size),
                        if (v.isActive) l.versionActive,
                        if (v.conflict) l.versionDivergent,
                        if (v.pinned) l.versionPinned,
                        if (v.savedAtReported != null) l.versionClockFixed,
                        if (v.sizeEvent != null) _sizeEvent(l, v.sizeEvent!, v.size),
                        if (v.note.isNotEmpty) l.versionNote(v.note),
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
                    child: TextButton(onPressed: _load, child: Text(l.olderVersions)),
                  ),
              ],
            ),
    );
  }
}
