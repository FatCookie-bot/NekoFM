Duration clampPlaybackPosition(Duration position, Duration duration) {
  if (duration <= Duration.zero) {
    return Duration.zero;
  }

  if (position > duration) {
    return duration;
  }

  if (position < Duration.zero) {
    return Duration.zero;
  }

  return position;
}

String formatPlaybackDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes < 60) {
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
