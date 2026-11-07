import 'json_file.dart';

/// How the device token is stored.
enum TokenStorage {
  /// System keyring through the Secret Service API (libsecret). Default.
  keyring,

  /// Plain file with 0600 permissions, explicitly chosen by the user.
  file,
}

/// How the emulator is installed.
enum LaunchMode { native, flatpak }

/// Settings of an emulator profile (defaults per platform in
/// emulators/registry.dart).
class EmulatorSettings {
  EmulatorSettings({
    this.id = 'melonds',
    this.mode = LaunchMode.native,
    this.executable = 'melonDS',
    this.flatpakId = 'net.kuribo64.melonDS',
    List<String>? extraArgs,
    this.saveDirOverride,
  }) : extraArgs = extraArgs ?? const [];

  final String id;
  final LaunchMode mode;

  /// Executable for the native mode (a name looked up in PATH, or a path).
  final String executable;
  final String flatpakId;

  /// Extra arguments passed before the ROM.
  final List<String> extraArgs;

  /// Save folder chosen by the user; null = detected from the emulator's
  /// configuration (next to the ROM by default).
  final String? saveDirOverride;

  EmulatorSettings copyWith({
    LaunchMode? mode,
    String? executable,
    String? flatpakId,
    List<String>? extraArgs,
    String? Function()? saveDirOverride,
  }) => EmulatorSettings(
    id: id,
    mode: mode ?? this.mode,
    executable: executable ?? this.executable,
    flatpakId: flatpakId ?? this.flatpakId,
    extraArgs: extraArgs ?? this.extraArgs,
    saveDirOverride: saveDirOverride != null ? saveDirOverride() : this.saveDirOverride,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'mode': mode.name,
    'executable': executable,
    'flatpak_id': flatpakId,
    'extra_args': extraArgs,
    'save_dir_override': saveDirOverride,
  };

  factory EmulatorSettings.fromJson(Map<String, Object?> j) => EmulatorSettings(
    id: (j['id'] as String?) ?? 'melonds',
    mode: LaunchMode.values.byName((j['mode'] as String?) ?? 'native'),
    executable: (j['executable'] as String?) ?? 'melonDS',
    flatpakId: (j['flatpak_id'] as String?) ?? 'net.kuribo64.melonDS',
    extraArgs: [for (final a in (j['extra_args'] as List<Object?>?) ?? const []) a! as String],
    saveDirOverride: j['save_dir_override'] as String?,
  );
}

/// What the user decided for a ROM whose game identifier is shared with
/// other local ROMs.
class RomChoice {
  const RomChoice.share() : customId = null;
  const RomChoice.separate(String this.customId);

  /// Forced `x:` identifier when the ROM is separated; null when it shares
  /// the save of its game.
  final String? customId;

  bool get shares => customId == null;

  Map<String, Object?> toJson() => {
    'choice': shares ? 'share' : 'separate',
    if (customId != null) 'custom_id': customId,
  };

  factory RomChoice.fromJson(Map<String, Object?> j) =>
      j['choice'] == 'separate' ? RomChoice.separate(j['custom_id']! as String) : const RomChoice.share();
}

/// Client settings, stored in `~/.config/romsync/config.json`.
class ClientConfig {
  ClientConfig({
    this.serverUrl,
    this.deviceName,
    this.deviceId,
    List<String>? romFolders,
    Map<String, EmulatorSettings>? emulators,
    this.defaultEmulator = 'melonds',
    Map<String, String>? gameEmulators,
    this.backupCount = 10,
    this.tokenStorage = TokenStorage.keyring,
    Map<String, RomChoice>? romChoices,
  }) : romFolders = romFolders ?? [],
       emulators = emulators ?? {},
       gameEmulators = gameEmulators ?? {},
       romChoices = romChoices ?? {};

  String? serverUrl;
  String? deviceName;
  int? deviceId;
  final List<String> romFolders;

  /// Settings changed by the user, by emulator id; missing ones use the
  /// platform defaults.
  final Map<String, EmulatorSettings> emulators;

  /// Emulator used for games without their own choice.
  String defaultEmulator;

  /// Emulator chosen for a game, by game identifier.
  final Map<String, String> gameEmulators;

  /// Emulator of [gameId].
  String emulatorFor(String gameId) => gameEmulators[gameId] ?? defaultEmulator;

  /// Number of `.backup` copies kept per save file.
  int backupCount;
  TokenStorage tokenStorage;

  /// Choices for ROMs sharing a game identifier, by ROM key.
  final Map<String, RomChoice> romChoices;

  bool get isPaired => serverUrl != null && deviceId != null;

  Map<String, Object?> toJson() => {
    'server_url': serverUrl,
    'device_name': deviceName,
    'device_id': deviceId,
    'rom_folders': romFolders,
    'emulators': {for (final e in emulators.entries) e.key: e.value.toJson()},
    'default_emulator': defaultEmulator,
    'game_emulators': gameEmulators,
    'backup_count': backupCount,
    'token_storage': tokenStorage.name,
    'rom_choices': {for (final e in romChoices.entries) e.key: e.value.toJson()},
  };

  factory ClientConfig.fromJson(Map<String, Object?> j) => ClientConfig(
    serverUrl: j['server_url'] as String?,
    deviceName: j['device_name'] as String?,
    deviceId: j['device_id'] as int?,
    romFolders: [for (final f in (j['rom_folders'] as List<Object?>?) ?? const []) f! as String],
    emulators: {
      for (final e in ((j['emulators'] as Map<String, Object?>?) ?? const {}).entries)
        e.key: EmulatorSettings.fromJson(e.value! as Map<String, Object?>),
      // Phase 2 format: a single melonDS profile.
      if (j['emulators'] == null && j['emulator'] != null)
        'melonds': EmulatorSettings.fromJson(j['emulator']! as Map<String, Object?>),
    },
    defaultEmulator: (j['default_emulator'] as String?) ?? 'melonds',
    gameEmulators: {
      for (final e in ((j['game_emulators'] as Map<String, Object?>?) ?? const {}).entries) e.key: e.value! as String,
    },
    backupCount: (j['backup_count'] as int?) ?? 10,
    tokenStorage: TokenStorage.values.byName((j['token_storage'] as String?) ?? 'keyring'),
    romChoices: {
      for (final e in ((j['rom_choices'] as Map<String, Object?>?) ?? const {}).entries)
        e.key: RomChoice.fromJson(e.value! as Map<String, Object?>),
    },
  );

  static Future<ClientConfig> load(String path) async {
    final j = await JsonFile(path).read();
    return j == null ? ClientConfig() : ClientConfig.fromJson(j as Map<String, Object?>);
  }

  Future<void> save(String path) => JsonFile(path).write(toJson());
}
