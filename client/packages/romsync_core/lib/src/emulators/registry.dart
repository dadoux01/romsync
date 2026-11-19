import '../rom/game_system.dart';
import '../state/config.dart';
import 'desmume.dart';
import 'emulator.dart';
import 'melonds.dart';
import 'mgba.dart';
import 'retroarch.dart';

/// Emulators supported by the client, by console, in the order shown to the
/// user; the first of each console is its default.
const emulatorIdsBySystem = {
  GameSystem.nds: ['melonds', 'desmume', 'retroarch-melondsds'],
  GameSystem.gba: ['mgba', 'retroarch-mgba'],
};

/// Every emulator, console after console.
final emulatorIds = [for (final ids in emulatorIdsBySystem.values) ...ids];

/// Emulators of [system].
List<String> emulatorIdsFor(GameSystem system) => emulatorIdsBySystem[system] ?? const [];

/// Console of an emulator id.
GameSystem systemOfEmulator(String id) => emulatorIdsBySystem.entries
    .firstWhere((e) => e.value.contains(id), orElse: () => const MapEntry(GameSystem.nds, []))
    .key;

/// Display name of an emulator id.
String emulatorName(String id) => switch (id) {
  'melonds' => 'melonDS',
  'desmume' => 'DeSmuME',
  'retroarch-melondsds' => 'RetroArch (melonDS DS)',
  'mgba' => 'mGBA',
  'retroarch-mgba' => 'RetroArch (mGBA)',
  _ => id,
};

/// Default settings of an emulator on [platform]: the usual executable
/// name or install location, and its Flathub id.
EmulatorSettings defaultEmulatorSettings(String id, HostPlatform platform) {
  final (exe, flatpak) = switch ((id, platform)) {
    ('melonds', HostPlatform.linux) => ('melonDS', 'net.kuribo64.melonDS'),
    ('melonds', HostPlatform.macos) => ('/Applications/melonDS.app', 'net.kuribo64.melonDS'),
    ('melonds', HostPlatform.windows) => ('melonDS.exe', 'net.kuribo64.melonDS'),
    ('desmume', HostPlatform.linux) => ('desmume', 'org.desmume.DeSmuME'),
    ('desmume', HostPlatform.macos) => ('/Applications/DeSmuME.app', 'org.desmume.DeSmuME'),
    ('desmume', HostPlatform.windows) => ('DeSmuME.exe', 'org.desmume.DeSmuME'),
    ('retroarch-melondsds' || 'retroarch-mgba', HostPlatform.linux) => ('retroarch', 'org.libretro.RetroArch'),
    ('retroarch-melondsds' || 'retroarch-mgba', HostPlatform.macos) => (
      '/Applications/RetroArch.app',
      'org.libretro.RetroArch',
    ),
    ('retroarch-melondsds' || 'retroarch-mgba', HostPlatform.windows) => (
      r'C:\RetroArch-Win64\retroarch.exe',
      'org.libretro.RetroArch',
    ),
    ('mgba', HostPlatform.linux) => ('mgba-qt', 'io.mgba.mGBA'),
    ('mgba', HostPlatform.macos) => ('/Applications/mGBA.app', 'io.mgba.mGBA'),
    ('mgba', HostPlatform.windows) => ('mGBA.exe', 'io.mgba.mGBA'),
    _ => throw ArgumentError('unknown emulator $id'),
  };
  return EmulatorSettings(id: id, executable: exe, flatpakId: flatpak);
}

/// Settings of [id]: the user's, else the platform defaults.
EmulatorSettings emulatorSettings(ClientConfig config, String id, HostPlatform platform) =>
    config.emulators[id] ?? defaultEmulatorSettings(id, platform);

/// Builds the profile of an emulator.
EmulatorProfile createEmulator(
  EmulatorSettings settings, {
  HostPlatform? platform,
  String? home,
  Map<String, String>? environment,
  CommandRunner? run,
  String? searchPath,
}) => switch (settings.id) {
  'melonds' => MelonDS(
    settings: settings,
    platform: platform,
    home: home,
    environment: environment,
    run: run,
    searchPath: searchPath,
  ),
  'desmume' => DeSmuME(
    settings: settings,
    platform: platform,
    home: home,
    environment: environment,
    run: run,
    searchPath: searchPath,
  ),
  'retroarch-melondsds' => RetroArchMelonDSDS(
    settings: settings,
    platform: platform,
    home: home,
    environment: environment,
    run: run,
    searchPath: searchPath,
  ),
  'mgba' => MGBA(
    settings: settings,
    platform: platform,
    home: home,
    environment: environment,
    run: run,
    searchPath: searchPath,
  ),
  'retroarch-mgba' => RetroArchMGBA(
    settings: settings,
    platform: platform,
    home: home,
    environment: environment,
    run: run,
    searchPath: searchPath,
  ),
  _ => throw ArgumentError('unknown emulator ${settings.id}'),
};
