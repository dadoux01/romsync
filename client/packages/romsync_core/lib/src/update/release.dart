import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart' show Signature, VerifyKey;

import '../api/models.dart';

/// Version of this client, set at build time
/// (`--dart-define=ROMSYNC_VERSION=0.5.0`); "dev" for a local build, which
/// never updates itself.
const romsyncClientVersion = String.fromEnvironment('ROMSYNC_VERSION', defaultValue: 'dev');

/// Ed25519 public key of the releases (docs/releasing.md), the same as
/// keys/release-ed25519.pub (a test checks it).
const releasePublicKey = 'XefK8zbkiB+PmUAtb43o6JR3AawkvJdgSBIv2me7kJQ=';

/// A release version: MAJOR.MINOR.PATCH with an optional pre-release
/// suffix, as server/internal/updates.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch, [this.pre = '']);
  final int major, minor, patch;
  final String pre;

  static final _re = RegExp(r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.]+))?$');

  static ReleaseVersion? tryParse(String s) {
    final m = _re.firstMatch(s.trim());
    if (m == null) return null;
    return ReleaseVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), m[4] ?? '');
  }

  /// A pre-release is older than its release (0.5.0-rc1 < 0.5.0).
  @override
  int compareTo(ReleaseVersion other) {
    for (final (a, b) in [(major, other.major), (minor, other.minor), (patch, other.patch)]) {
      if (a != b) return a < b ? -1 : 1;
    }
    if (pre == other.pre) return 0;
    if (pre.isEmpty) return 1;
    if (other.pre.isEmpty) return -1;
    return pre.compareTo(other.pre).sign;
  }

  bool operator >(ReleaseVersion o) => compareTo(o) > 0;
  bool operator <(ReleaseVersion o) => compareTo(o) < 0;

  @override
  bool operator ==(Object other) => other is ReleaseVersion && compareTo(other) == 0;
  @override
  int get hashCode => Object.hash(major, minor, patch, pre);
  @override
  String toString() => '$major.$minor.$patch${pre.isEmpty ? '' : '-$pre'}';
}

/// Whether [update] should be offered to a client at [current]: final
/// releases only, strictly newer (never a downgrade), and never for a
/// development build.
bool isUpdate(String update, String current) {
  final u = ReleaseVersion.tryParse(update);
  final c = ReleaseVersion.tryParse(current);
  return u != null && c != null && u.pre.isEmpty && u > c;
}

/// Release platform of this computer (the end of the release file names).
String? currentUpdatePlatform() => switch (Abi.current()) {
  Abi.linuxX64 => 'linux-x64',
  Abi.linuxArm64 => 'linux-arm64',
  Abi.macosArm64 || Abi.macosX64 => 'macos',
  Abi.windowsX64 => 'windows-x64',
  _ => null,
};

class UpdateVerificationException implements Exception {
  UpdateVerificationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Checks a downloaded release file: the Ed25519 signature of SHA256SUMS
/// ([signature] is the base64 content of SHA256SUMS.sig) with [publicKey],
/// then the SHA-256 of [file] against its line in SHA256SUMS. Throws
/// [UpdateVerificationException] on any mismatch.
Future<void> verifyReleaseFile({
  required Uint8List sums,
  required String signature,
  required String fileName,
  required File file,
  String publicKey = releasePublicKey,
}) async {
  final Uint8List sig;
  final Uint8List key;
  try {
    sig = base64.decode(signature.trim());
    key = base64.decode(publicKey);
  } on FormatException {
    throw UpdateVerificationException('Signature illisible : mise à jour refusée.');
  }
  var valid = false;
  try {
    valid = sig.length == 64 && key.length == 32 && VerifyKey(key).verify(signature: Signature(sig), message: sums);
  } catch (_) {
    valid = false;
  }
  if (!valid) {
    throw UpdateVerificationException(
      'Signature invalide : cette mise à jour ne vient pas de RomSync, elle est refusée.',
    );
  }
  final expected = sumFor(utf8.decode(sums, allowMalformed: true), fileName);
  if (expected == null) {
    throw UpdateVerificationException('$fileName ne figure pas dans SHA256SUMS : mise à jour refusée.');
  }
  final actual = (await sha256.bind(file.openRead()).first).toString();
  if (actual != expected) {
    throw UpdateVerificationException('Le fichier téléchargé est altéré (hash différent) : mise à jour refusée.');
  }
}

/// The SHA-256 of [name] in a `sha256sum` output (`<hex>  <name>` or
/// `<hex> *<name>`).
String? sumFor(String sums, String name) {
  for (final line in const LineSplitter().convert(sums)) {
    final m = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$').firstMatch(line.trimRight());
    if (m != null && m[2] == name) return m[1]!.toLowerCase();
  }
  return null;
}

/// Server level needed by this client (docs/SPEC.md, "Compatibilité"): 2 is
/// X-Activate, the user's choice after a divergence.
const requiredServerApiLevel = 2;

enum Compatibility {
  ok,

  /// The server is older than this client needs: update the server.
  serverTooOld,

  /// This client is older than the server accepts: update the app.
  clientTooOld,
}

/// Compares this client with the server ([info] null: a server older than
/// 0.5.0).
Compatibility checkCompatibility(ServerInfo? info, {String clientVersion = romsyncClientVersion}) {
  if (info == null || info.apiLevel < requiredServerApiLevel) return Compatibility.serverTooOld;
  final min = ReleaseVersion.tryParse(info.minClientVersion);
  final me = ReleaseVersion.tryParse(clientVersion);
  if (min != null && me != null && me < min) return Compatibility.clientTooOld;
  return Compatibility.ok;
}

/// Message shown for an incompatibility.
String compatibilityMessage(Compatibility c, ServerInfo? info) => switch (c) {
  Compatibility.ok => '',
  Compatibility.serverTooOld =>
    'Le serveur RomSync (${info?.version ?? 'version antérieure à 0.5.0'}) est trop ancien pour cette appli : '
        'mets d’abord à jour le serveur (nouvelle image Docker). En attendant, le choix en cas de divergence '
        'n’est pas disponible.',
  Compatibility.clientTooOld =>
    'Cette appli ($romsyncClientVersion) est trop ancienne pour le serveur, qui demande au moins '
        '${info?.minClientVersion} : mets-la à jour.',
};
