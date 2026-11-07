import 'dart:io';

import 'package:path/path.dart' as p;

import 'game_id.dart';
import 'nds_header.dart';
import 'rom_file.dart';
import 'seven_zip.dart';
import 'zip_reader.dart';

/// A ROM found by [RomScanner], with the identifier derived from its header.
class ScannedRom {
  ScannedRom({required this.file, required this.header, required this.detectedId});

  final RomFile file;

  /// Parsed header, or null when the ROM is too short to have one.
  final NdsHeader? header;

  /// Identifier derived from the ROM: its cartridge code, or `h:<sha1>` when
  /// it has no valid code (docs/SPEC.md, "Identification des jeux").
  final String detectedId;

  /// Title shown by default: the internal title, or the file name.
  String get title {
    final t = header?.title ?? '';
    return t.isNotEmpty ? t : p.basenameWithoutExtension(file.romName);
  }
}

/// Something that prevented a file from being read.
class ScanIssue {
  ScanIssue(this.path, this.message);
  final String path;
  final String message;
  @override
  String toString() => '$path: $message';
}

class ScanResult {
  ScanResult(this.roms, this.issues);
  final List<ScannedRom> roms;
  final List<ScanIssue> issues;
}

/// Finds the DS ROMs in folders: .nds files, and .nds inside .zip (read in
/// pure Dart) and .7z archives (read with an external 7-Zip program).
class RomScanner {
  RomScanner({SevenZip? sevenZip, bool findSevenZip = true})
    : sevenZip = sevenZip ?? (findSevenZip ? SevenZip.find() : null);

  /// The 7-Zip program, or null when none is installed.
  final SevenZip? sevenZip;

  static const installSevenZipMessage = 'Installer 7zip (paquet p7zip ou 7zip) pour lire les archives .7z.';

  Future<ScanResult> scan(Iterable<String> folders) async {
    final roms = <ScannedRom>[];
    final issues = <ScanIssue>[];
    for (final folder in folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) {
        issues.add(ScanIssue(folder, 'dossier introuvable'));
        continue;
      }
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        // Skip hidden folders such as .backup.
        final rel = p.relative(entity.path, from: folder);
        if (p.split(rel).any((part) => part.startsWith('.'))) continue;
        final ext = p.extension(entity.path).toLowerCase();
        try {
          switch (ext) {
            case '.nds':
              roms.add(await identify(PlainRomFile(entity.path)));
            case '.zip':
              final zip = await ZipReader.open(entity.path);
              for (final e in zip.entries) {
                if (p.extension(e.name).toLowerCase() != '.nds') continue;
                if (!e.isSupported) {
                  issues.add(ScanIssue('${entity.path}#${e.name}', 'compression non prise en charge'));
                  continue;
                }
                roms.add(await identify(ZipRomFile(entity.path, zip, e)));
              }
            case '.7z':
              final tool = sevenZip;
              if (tool == null) {
                issues.add(ScanIssue(entity.path, installSevenZipMessage));
                continue;
              }
              for (final name in await tool.list(entity.path)) {
                if (p.extension(name).toLowerCase() != '.nds') continue;
                roms.add(await identify(SevenZipRomFile(entity.path, tool, name)));
              }
          }
        } catch (e) {
          issues.add(ScanIssue(entity.path, 'illisible : $e'));
        }
      }
    }
    roms.sort((a, b) => a.file.key.compareTo(b.file.key));
    return ScanResult(roms, issues);
  }

  /// Reads the header of [file] and derives its identifier. The SHA-1 of the
  /// whole ROM is only computed when the header has no valid code.
  static Future<ScannedRom> identify(RomFile file) async {
    final header = NdsHeader.parse(await file.readStart(NdsHeader.length));
    final id = header != null && header.hasValidCode ? header.gameCode : GameId.fromRomSha1(await file.sha1Hex());
    return ScannedRom(file: file, header: header, detectedId: id);
  }
}
