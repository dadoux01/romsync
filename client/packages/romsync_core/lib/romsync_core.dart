/// Platform-independent logic of the RomSync client.
library;

export 'src/api/api_client.dart';
export 'src/api/models.dart';
export 'src/profiles/profile.dart';
export 'src/rom/game_id.dart';
export 'src/rom/nds_header.dart';
export 'src/rom/rom_file.dart';
export 'src/rom/scanner.dart';
export 'src/rom/seven_zip.dart';
export 'src/rom/zip_reader.dart';
export 'src/state/config.dart';
export 'src/state/json_file.dart';
export 'src/state/save_state.dart';
export 'src/state/upload_queue.dart';
export 'src/sync/backups.dart';
export 'src/sync/engine.dart';
export 'src/sync/library.dart';
export 'src/sync/play_session.dart';
export 'src/sync/status.dart';
export 'src/sync/watcher.dart';

/// Version of the client, shown in the interface.
const romsyncClientVersion = '0.1.0';
