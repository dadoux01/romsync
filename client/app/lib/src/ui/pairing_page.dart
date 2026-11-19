import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import '../l10n.dart';

/// First screen: server address, pairing code and device name.
class PairingPage extends StatefulWidget {
  const PairingPage({super.key, required this.controller, this.defaultDeviceName = 'Linux'});
  final AppController controller;
  final String defaultDeviceName;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _form = GlobalKey<FormState>();
  late final _server = TextEditingController(text: widget.controller.config.serverUrl ?? '');
  final _code = TextEditingController();
  late final _name = TextEditingController(text: widget.defaultDeviceName);
  bool _busy = false;
  String? _error;

  static String? validateServer(AppLocalizations l, String? v) {
    if (v == null || v.trim().isEmpty) return l.pairServerRequired;
    try {
      RomSyncApi.normalizeServerUrl(v);
      return null;
    } on FormatException {
      return l.pairServerInvalid;
    }
  }

  static String? validateCode(AppLocalizations l, String? v) =>
      RegExp(r'^[A-Za-z0-9]{4}-?[A-Za-z0-9]{4}$').hasMatch((v ?? '').trim()) ? null : l.pairCodeInvalid;

  Future<void> _submit({bool allowFile = false}) async {
    if (!_form.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.pair(
        serverUrl: _server.text,
        code: _code.text.trim(),
        deviceName: _name.text.trim(),
        allowFileStorage: allowFile,
      );
    } on KeyringUnavailableException {
      if (!mounted) return;
      final accept = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.pairNoKeyringTitle),
          content: Text('${l.pairNoKeyringBody}\n\n${l.tokenFileWarning}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
            FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: Text(l.pairUseFile)),
          ],
        ),
      );
      if (accept == true) return _submit(allowFile: true);
    } on ApiException catch (e) {
      setState(
        () => _error = switch (e.code) {
          'expired' => l.pairCodeExpired,
          'not_found' => l.pairCodeUnknown,
          'rate_limited' => l.rateLimited,
          _ => e.message,
        },
      );
    } on ServerUnreachableException {
      setState(() => _error = l.pairUnreachable);
    } catch (e) {
      setState(() => _error = errorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.pairTitle, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(l.pairIntro),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _server,
                      decoration: InputDecoration(labelText: l.pairServer, hintText: 'http://nas:8080'),
                      validator: (v) => validateServer(l, v),
                    ),
                    TextFormField(
                      controller: _code,
                      decoration: InputDecoration(labelText: l.pairCode, hintText: 'K7QM-4XPA'),
                      validator: (v) => validateCode(l, v),
                    ),
                    TextFormField(
                      controller: _name,
                      decoration: InputDecoration(labelText: l.pairName),
                      validator: (v) => (v ?? '').trim().isEmpty ? l.pairNameRequired : null,
                      maxLength: 64,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    FilledButton(onPressed: _busy ? null : _submit, child: Text(l.pairSubmit)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
