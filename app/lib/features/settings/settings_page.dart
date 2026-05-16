import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../core/downloads/download_preferences.dart';
import '../../core/player/playback_preferences.dart';
import '../../core/server/music_server_client.dart';
import '../../core/server/secure_server_profile_store.dart';
import '../../core/server/server_profile.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController(
    text: 'http://127.0.0.1:4533',
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _downloadFolderController = TextEditingController();
  final _store = const SecureServerProfileStore();
  final _client = MusicServerClient();
  final _playbackPreferences = PlaybackPreferences();
  final _downloadPreferences = DownloadPreferences();

  bool _rememberPassword = true;
  bool _isPasswordVisible = false;
  bool _isLoadingProfile = true;
  bool _isTestingConnection = false;
  bool _isScanningServer = false;
  double _previousTrackThresholdSeconds = PlaybackPreferences
      .defaultPreviousTrackThreshold
      .inSeconds
      .toDouble();
  String? _connectionStep;
  String? _scanMessage;
  String? _profileLoadWarning;
  String? _preferencesWarning;
  String? _downloadFolderMessage;
  String? _downloadFolderWarning;
  ServerConnectionResult? _connectionResult;

  @override
  void initState() {
    super.initState();
    _loadSavedProfile();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _downloadFolderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;
    final profilePreview = _buildProfile();
    final showHttpWarning = profilePreview?.usesPublicHttp ?? false;

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'Server connection',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Connect directly to your own Navidrome or Subsonic-compatible server.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (_profileLoadWarning != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  icon: Icons.info_outline,
                  message: _profileLoadWarning!,
                  color: colorScheme.tertiary,
                ),
              ],
              const SizedBox(height: 24),
              TextFormField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'http://127.0.0.1:4533',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                validator: _validateServerUrl,
                onChanged: (_) => setState(() {
                  _connectionResult = null;
                }),
              ),
              if (showHttpWarning) ...[
                const SizedBox(height: 8),
                _InlineNotice(
                  icon: Icons.warning_amber_outlined,
                  message:
                      'Public HTTP is not encrypted. Use HTTPS for remote servers.',
                  color: colorScheme.tertiary,
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: _requiredField('Enter your server username.'),
                onChanged: (_) => setState(() {
                  _connectionResult = null;
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _isPasswordVisible
                        ? 'Hide password'
                        : 'Show password',
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                obscureText: !_isPasswordVisible,
                textInputAction: TextInputAction.done,
                validator: _requiredField('Enter your server password.'),
                onChanged: (_) => setState(() {
                  _connectionResult = null;
                }),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _rememberPassword,
                onChanged: (value) {
                  setState(() {
                    _rememberPassword = value ?? true;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember credentials on this device'),
                subtitle: const Text(
                  'Saved locally in secure OS storage. NekoFM has no cloud account.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isTestingConnection ? null : _testConnection,
                icon: _isTestingConnection
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lan_outlined),
                label: Text(
                  _isTestingConnection ? 'Testing...' : 'Test connection',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isScanningServer ? null : _scanServerLibrary,
                icon: _isScanningServer
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search_outlined),
                label: Text(
                  _isScanningServer ? 'Scanning...' : 'Scan server library',
                ),
              ),
              if (_connectionStep != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  icon: Icons.sync_outlined,
                  message: _connectionStep!,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
              if (_scanMessage != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  icon: Icons.library_music_outlined,
                  message: _scanMessage!,
                  color: colorScheme.primary,
                ),
              ],
              if (_connectionResult != null) ...[
                const SizedBox(height: 16),
                _ConnectionStatus(result: _connectionResult!),
              ],
              const SizedBox(height: 32),
              Text('Playback', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Choose how the previous-track button behaves after a song has already started.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _PreviousTrackThresholdControl(
                value: _previousTrackThresholdSeconds,
                onChanged: _setPreviousTrackThreshold,
              ),
              if (_preferencesWarning != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  icon: Icons.info_outline,
                  message: _preferencesWarning!,
                  color: colorScheme.tertiary,
                ),
              ],
              const SizedBox(height: 32),
              Text('Downloads', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Choose where new downloaded tracks are saved. Existing downloads keep their saved paths.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _downloadFolderController,
                decoration: const InputDecoration(
                  labelText: 'Download folder',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _chooseDownloadFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Choose folder'),
                  ),
                  FilledButton.icon(
                    onPressed: _saveDownloadFolder,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save folder'),
                  ),
                  TextButton.icon(
                    onPressed: _resetDownloadFolder,
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('Use default'),
                  ),
                ],
              ),
              if (_downloadFolderMessage != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  icon: Icons.check_circle_outline,
                  message: _downloadFolderMessage!,
                  color: colorScheme.primary,
                ),
              ],
              if (_downloadFolderWarning != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  icon: Icons.warning_amber_outlined,
                  message: _downloadFolderWarning!,
                  color: colorScheme.tertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadSavedProfile() async {
    SavedServerProfile? savedProfile;
    String? loadWarning;

    try {
      savedProfile = await _store.load().timeout(const Duration(seconds: 2));
    } on Object catch (error) {
      loadWarning = 'Saved profile could not be loaded: $error';
    }

    final threshold = await _loadPreviousTrackThreshold();
    final downloadFolder = await _loadDownloadFolder();

    if (!mounted) {
      return;
    }

    if (savedProfile != null) {
      _serverUrlController.text = savedProfile.serverUrl;
      _usernameController.text = savedProfile.username;
      _passwordController.text = savedProfile.password;
      _rememberPassword = savedProfile.rememberPassword;
    }

    setState(() {
      _isLoadingProfile = false;
      _profileLoadWarning = loadWarning;
      _previousTrackThresholdSeconds = threshold.inSeconds.toDouble();
      _downloadFolderController.text = downloadFolder;
    });
  }

  Future<Duration> _loadPreviousTrackThreshold() async {
    try {
      return await _playbackPreferences.loadPreviousTrackThreshold().timeout(
        const Duration(seconds: 2),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _preferencesWarning =
              'Playback preferences could not be loaded: $error';
        });
      }

      return PlaybackPreferences.defaultPreviousTrackThreshold;
    }
  }

  Future<String> _loadDownloadFolder() async {
    try {
      final customFolder = await _downloadPreferences
          .loadCustomDownloadFolder()
          .timeout(const Duration(seconds: 2));
      if (customFolder != null) {
        return customFolder;
      }

      final defaultFolder = await _downloadPreferences
          .defaultDownloadFolder()
          .timeout(const Duration(seconds: 2));
      return defaultFolder.path;
    } on Object catch (error) {
      _downloadFolderWarning = 'Download folder could not be loaded: $error';
      return '';
    }
  }

  Future<void> _setPreviousTrackThreshold(double value) async {
    final roundedValue = value.roundToDouble();
    setState(() {
      _previousTrackThresholdSeconds = roundedValue;
      _preferencesWarning = null;
    });

    try {
      await _playbackPreferences
          .savePreviousTrackThreshold(Duration(seconds: roundedValue.toInt()))
          .timeout(const Duration(seconds: 2));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _preferencesWarning = 'Playback preference could not be saved: $error';
      });
    }
  }

  Future<void> _chooseDownloadFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Use this folder',
      initialDirectory: _downloadFolderController.text.trim().isEmpty
          ? null
          : _downloadFolderController.text.trim(),
    );
    if (path == null || !mounted) {
      return;
    }

    setState(() {
      _downloadFolderController.text = path;
      _downloadFolderMessage = null;
      _downloadFolderWarning = null;
    });
  }

  Future<void> _saveDownloadFolder() async {
    final path = _downloadFolderController.text.trim();
    if (path.isEmpty) {
      setState(() {
        _downloadFolderMessage = null;
        _downloadFolderWarning = 'Choose a folder before saving.';
      });
      return;
    }

    try {
      await _downloadPreferences.saveCustomDownloadFolder(path);
      if (!mounted) {
        return;
      }

      setState(() {
        _downloadFolderMessage = 'New downloads will be saved to this folder.';
        _downloadFolderWarning = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _downloadFolderMessage = null;
        _downloadFolderWarning = 'Download folder could not be saved: $error';
      });
    }
  }

  Future<void> _resetDownloadFolder() async {
    try {
      await _downloadPreferences.clearCustomDownloadFolder();
      final defaultFolder = await _downloadPreferences.defaultDownloadFolder();
      if (!mounted) {
        return;
      }

      setState(() {
        _downloadFolderController.text = defaultFolder.path;
        _downloadFolderMessage = 'New downloads will use the default folder.';
        _downloadFolderWarning = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _downloadFolderMessage = null;
        _downloadFolderWarning = 'Default folder could not be restored: $error';
      });
    }
  }

  Future<void> _testConnection() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _connectionStep = 'Preparing secure Subsonic auth...';
      _scanMessage = null;
      _connectionResult = null;
    });

    final savedProfile = SavedServerProfile(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      rememberPassword: _rememberPassword,
    );
    setState(() {
      _connectionStep = 'Contacting server...';
    });

    var result = await _client
        .testConnection(savedProfile.toServerProfile())
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => const ServerConnectionResult.failure(
            'Connection test timed out before the server answered.',
          ),
        );

    if (result.isSuccess) {
      if (mounted) {
        setState(() {
          _connectionStep = 'Saving server profile...';
        });
      }
      result = await _saveProfileSafely(savedProfile);
    }

    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _connectionStep = null;
        _connectionResult = result;
      });
    }
  }

  Future<void> _scanServerLibrary() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isScanningServer = true;
      _scanMessage = 'Asking server to scan the music folder...';
      _connectionResult = null;
    });

    final savedProfile = SavedServerProfile(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      rememberPassword: _rememberPassword,
    );

    try {
      final result = await _client
          .startScan(savedProfile)
          .timeout(const Duration(seconds: 15));

      if (!mounted) {
        return;
      }

      setState(() {
        _scanMessage = result.message;
      });
    } on MusicServerException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _scanMessage = 'Server scan failed: ${error.message}';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _scanMessage = 'Server scan failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanningServer = false;
        });
      }
    }
  }

  Future<ServerConnectionResult> _saveProfileSafely(
    SavedServerProfile profile,
  ) async {
    try {
      await _store.save(profile).timeout(const Duration(seconds: 3));
      return const ServerConnectionResult.success();
    } on Object catch (error) {
      return ServerConnectionResult.success(
        'Connection works. Credentials were not saved: $error',
      );
    }
  }

  ServerProfile? _buildProfile() {
    try {
      final profile = ServerProfile(
        serverUrl: _serverUrlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );
      profile.normalizedBaseUri;
      return profile;
    } on FormatException {
      return null;
    }
  }

  String? Function(String?) _requiredField(String message) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return message;
      }
      return null;
    };
  }

  String? _validateServerUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your server URL.';
    }

    try {
      ServerProfile(
        serverUrl: value,
        username: 'validation',
        password: 'validation',
      ).normalizedBaseUri;
    } on FormatException catch (error) {
      return error.message;
    }

    return null;
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.result});

  final ServerConnectionResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = result.isSuccess ? colorScheme.primary : colorScheme.error;

    return _InlineNotice(
      icon: result.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
      message: result.message,
      color: color,
    );
  }
}

class _PreviousTrackThresholdControl extends StatelessWidget {
  const _PreviousTrackThresholdControl({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final seconds = value.round();
    final label = seconds == 0
        ? 'Always go to previous track'
        : 'Restart current track after $seconds seconds';

    return Semantics(
      label: 'Previous track threshold',
      value: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Previous button threshold',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          Slider(
            value: value,
            min: PlaybackPreferences.minPreviousTrackThreshold.inSeconds
                .toDouble(),
            max: PlaybackPreferences.maxPreviousTrackThreshold.inSeconds
                .toDouble(),
            divisions:
                PlaybackPreferences.maxPreviousTrackThreshold.inSeconds -
                PlaybackPreferences.minPreviousTrackThreshold.inSeconds,
            label: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
