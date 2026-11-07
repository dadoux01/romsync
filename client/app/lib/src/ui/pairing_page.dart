import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';

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

  static String? validateServer(String? v) {
    if (v == null || v.trim().isEmpty) return 'Adresse du serveur requise';
    try {
      RomSyncApi.normalizeServerUrl(v);
      return null;
    } on FormatException {
      return 'Adresse invalide (ex. http://nas:8080)';
    }
  }

  static String? validateCode(String? v) => RegExp(r'^[A-Za-z0-9]{4}-?[A-Za-z0-9]{4}$').hasMatch((v ?? '').trim())
      ? null
      : 'Code de 8 caractères (ex. K7QM-4XPA)';

  Future<void> _submit({bool allowFile = false}) async {
    if (!_form.currentState!.validate()) return;
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
          title: const Text('Aucun trousseau disponible'),
          content: const Text(
            'RomSync range le jeton de l’appareil dans le trousseau du système (Secret Service : '
            'GNOME Keyring, KWallet, KeePassXC…), mais aucun ne répond dans cette session.\n\n'
            'Tu peux démarrer un trousseau puis réessayer, ou stocker le jeton dans un fichier.\n\n'
            '${FileTokenStore.warning}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Stocker le jeton dans un fichier'),
            ),
          ],
        ),
      );
      if (accept == true) return _submit(allowFile: true);
    } on ApiException catch (e) {
      setState(
        () => _error = switch (e.code) {
          'expired' => 'Ce code a expiré ou a déjà été utilisé : génère-en un nouveau sur le site.',
          'not_found' => 'Code inconnu : vérifie-le, ou génère-en un nouveau sur le site.',
          'rate_limited' => 'Trop de tentatives : réessaie dans une minute.',
          _ => e.message,
        },
      );
    } on ServerUnreachableException {
      setState(() => _error = 'Serveur injoignable : vérifie l’adresse et ta connexion (Tailscale ?).');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    Text('Appairer cet appareil', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text('Sur le site RomSync : Appareils → Ajouter un appareil, puis saisis le code ici.'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _server,
                      decoration: const InputDecoration(labelText: 'Adresse du serveur', hintText: 'http://nas:8080'),
                      validator: validateServer,
                    ),
                    TextFormField(
                      controller: _code,
                      decoration: const InputDecoration(labelText: 'Code d’appairage', hintText: 'K7QM-4XPA'),
                      validator: validateCode,
                    ),
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nom de l’appareil'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Nom requis' : null,
                      maxLength: 64,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    FilledButton(onPressed: _busy ? null : _submit, child: const Text('Appairer')),
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
