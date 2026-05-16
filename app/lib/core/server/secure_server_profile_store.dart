import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'server_profile.dart';

class SecureServerProfileStore {
  const SecureServerProfileStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(
              accountName: 'NekoFM',
              usesDataProtectionKeychain: false,
            ),
          );

  static const _serverUrlKey = 'server_profile.url';
  static const _usernameKey = 'server_profile.username';
  static const _passwordKey = 'server_profile.password';
  static const _rememberPasswordKey = 'server_profile.remember_password';

  final FlutterSecureStorage _storage;

  Future<SavedServerProfile?> load() async {
    final serverUrl = await _storage.read(key: _serverUrlKey);
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey) ?? '';
    final rememberPassword =
        await _storage.read(key: _rememberPasswordKey) == 'true';

    if (serverUrl == null || username == null) {
      return null;
    }

    return SavedServerProfile(
      serverUrl: serverUrl,
      username: username,
      password: password,
      rememberPassword: rememberPassword,
    );
  }

  Future<void> save(SavedServerProfile profile) async {
    await _storage.write(key: _serverUrlKey, value: profile.serverUrl);
    await _storage.write(key: _usernameKey, value: profile.username);
    await _storage.write(
      key: _rememberPasswordKey,
      value: profile.rememberPassword.toString(),
    );

    if (profile.rememberPassword) {
      await _storage.write(key: _passwordKey, value: profile.password);
    } else {
      await _storage.delete(key: _passwordKey);
    }
  }
}

class SavedServerProfile {
  const SavedServerProfile({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.rememberPassword,
  });

  final String serverUrl;
  final String username;
  final String password;
  final bool rememberPassword;

  ServerProfile toServerProfile() {
    return ServerProfile(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }
}
