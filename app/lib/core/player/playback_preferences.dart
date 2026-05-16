import 'package:shared_preferences/shared_preferences.dart';

class PlaybackPreferences {
  PlaybackPreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  static const defaultPreviousTrackThreshold = Duration(seconds: 3);
  static const minPreviousTrackThreshold = Duration.zero;
  static const maxPreviousTrackThreshold = Duration(seconds: 15);

  static const _previousTrackThresholdSecondsKey =
      'playback.previous_track_threshold_seconds';

  final SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  Future<Duration> loadPreviousTrackThreshold() async {
    final seconds = await _store.getInt(_previousTrackThresholdSecondsKey);
    return thresholdFromSeconds(seconds);
  }

  Future<void> savePreviousTrackThreshold(Duration threshold) {
    return _store.setInt(
      _previousTrackThresholdSecondsKey,
      clampThreshold(threshold).inSeconds,
    );
  }

  static Duration thresholdFromSeconds(int? seconds) {
    if (seconds == null) {
      return defaultPreviousTrackThreshold;
    }

    return clampThreshold(Duration(seconds: seconds));
  }

  static Duration clampThreshold(Duration threshold) {
    if (threshold < minPreviousTrackThreshold) {
      return minPreviousTrackThreshold;
    }

    if (threshold > maxPreviousTrackThreshold) {
      return maxPreviousTrackThreshold;
    }

    return threshold;
  }
}

bool shouldRestartCurrentTrack({
  required Duration position,
  required Duration threshold,
}) {
  return position >= PlaybackPreferences.clampThreshold(threshold);
}
