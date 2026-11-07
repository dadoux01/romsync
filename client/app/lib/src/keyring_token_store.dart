import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:romsync_core/romsync_core.dart';

/// Device token in the system keyring: the Secret Service API (libsecret:
/// GNOME Keyring, KWallet, KeePassXC…) on Linux, the login keychain on
/// macOS. Windows uses [WindowsCredentialStore] instead.
class KeyringTokenStore implements TokenStore {
  KeyringTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // macOS: the classic "login" keychain. The data protection
            // keychain needs a signed app with a keychain entitlement.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;
  static const _key = 'romsync_device_token';
  static const _probe = 'romsync_keyring_probe';

  /// Writes, reads back and deletes a probe value: the only reliable way to
  /// know whether a Secret Service answers (Hyprland sessions often have none).
  @override
  Future<bool> isAvailable() async {
    try {
      await _storage.write(key: _probe, value: 'ok');
      final ok = await _storage.read(key: _probe) == 'ok';
      await _storage.delete(key: _probe);
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
