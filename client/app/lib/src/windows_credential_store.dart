import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:romsync_core/romsync_core.dart';
import 'package:win32/win32.dart';

/// Device token in the Windows Credential Manager (generic credential named
/// "RomSync", visible in Control Panel > Credential Manager > Windows
/// Credentials), written with CredWriteW.
class WindowsCredentialStore implements TokenStore {
  WindowsCredentialStore({this.target = 'RomSync'});

  /// Name of the credential.
  final String target;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> read() async => using((arena) {
    final out = arena<Pointer<CREDENTIAL>>();
    final r = CredRead(target.toPcwstr(allocator: arena), CRED_TYPE_GENERIC, out);
    if (!r.value) {
      if (r.error == ERROR_NOT_FOUND) return null;
      throw WindowsException(r.error.toHRESULT());
    }
    try {
      final cred = out.value.ref;
      return utf8.decode(cred.CredentialBlob.asTypedList(cred.CredentialBlobSize));
    } finally {
      CredFree(out.value);
    }
  });

  @override
  Future<void> write(String token) async => using((arena) {
    final blob = utf8.encode(token);
    final data = arena<Uint8>(blob.length)..asTypedList(blob.length).setAll(0, blob);
    final cred = arena<CREDENTIAL>();
    cred.ref
      ..Type = CRED_TYPE_GENERIC
      ..TargetName = target.toPwstr(allocator: arena)
      ..UserName = 'device token'.toPwstr(allocator: arena)
      ..Comment = 'RomSync device token (revocable from the RomSync website)'.toPwstr(allocator: arena)
      ..CredentialBlobSize = blob.length
      ..CredentialBlob = data
      ..Persist = CRED_PERSIST_LOCAL_MACHINE;
    final r = CredWrite(cred, 0);
    if (!r.value) throw WindowsException(r.error.toHRESULT());
  });

  @override
  Future<void> delete() async => using((arena) {
    final r = CredDelete(target.toPcwstr(allocator: arena), CRED_TYPE_GENERIC);
    if (!r.value && r.error != ERROR_NOT_FOUND) throw WindowsException(r.error.toHRESULT());
  });
}
