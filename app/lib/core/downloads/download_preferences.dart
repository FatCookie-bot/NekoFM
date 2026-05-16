import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadPreferences {
  DownloadPreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  static const _downloadFolderKey = 'downloads.folder_path';

  final SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  Future<String?> loadCustomDownloadFolder() async {
    final path = await _store.getString(_downloadFolderKey);
    if (path == null || path.trim().isEmpty) {
      return null;
    }

    return path.trim();
  }

  Future<void> saveCustomDownloadFolder(String path) {
    return _store.setString(_downloadFolderKey, path.trim());
  }

  Future<void> clearCustomDownloadFolder() {
    return _store.remove(_downloadFolderKey);
  }

  Future<Directory> defaultDownloadFolder() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/downloads/tracks');
  }

  Future<Directory> activeDownloadFolder() async {
    final customPath = await loadCustomDownloadFolder();
    if (customPath != null) {
      return Directory(customPath);
    }

    return defaultDownloadFolder();
  }
}
