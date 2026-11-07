import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:romsync_core/romsync_core.dart';

import 'src/app_controller.dart';
import 'src/keyring_token_store.dart';
import 'src/ui/home_page.dart';
import 'src/ui/pairing_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(
    paths: ClientPaths.fromEnvironment(),
    keyring: KeyringTokenStore(),
    profiles: await loadBundledProfiles(rootBundle),
  );
  await controller.init();
  runApp(RomSyncApp(controller: controller));
}

/// Reads the conversion profiles bundled from the repository's profiles/.
Future<ProfileRegistry> loadBundledProfiles(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final names = manifest.listAssets().where((a) => a.startsWith('assets/profiles/') && a.endsWith('.json'));
  return ProfileRegistry.fromJsonStrings([for (final n in names) await bundle.loadString(n)]);
}

/// Root widget of the RomSync desktop client.
class RomSyncApp extends StatelessWidget {
  const RomSyncApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4F6DF5);
    return MaterialApp(
      title: 'RomSync',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => controller.isPaired
            ? HomePage(controller: controller)
            : PairingPage(controller: controller, defaultDeviceName: Platform.localHostname),
      ),
    );
  }
}
