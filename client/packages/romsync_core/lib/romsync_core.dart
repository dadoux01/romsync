/// Platform-independent logic of the RomSync client.
library;

export 'src/rom/game_id.dart';
export 'src/rom/nds_header.dart';
export 'src/rom/rom_file.dart';
export 'src/rom/scanner.dart';
export 'src/rom/seven_zip.dart';
export 'src/rom/zip_reader.dart';

/// Version of the client, shown in the interface.
const romsyncClientVersion = '0.1.0';
