import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/track.dart';
import 'liked_repository.dart';
import 'liked_track.dart';

final likedControllerProvider = Provider<LikedController>((ref) {
  final controller = LikedController();
  ref.onDispose(controller.dispose);
  return controller;
});

class LikedController extends ChangeNotifier {
  LikedController({LikedRepository? repository})
    : _repository = repository ?? LikedRepository();

  final LikedRepository _repository;

  List<LikedTrack> _tracks = const [];
  bool _isLoaded = false;

  List<LikedTrack> get tracks => _tracks;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _tracks = List.unmodifiable(await _repository.loadTracks());
    _isLoaded = true;
    notifyListeners();
  }

  bool isLiked(String trackId) {
    return _tracks.any((track) => track.trackId == trackId);
  }

  Future<void> toggleTrack(Track track) async {
    if (!_isLoaded) {
      await load();
    }

    await _repository.toggleTrack(track);
    await load();
  }

  Future<void> unlikeTrack(String trackId) async {
    await _repository.unlikeTrack(trackId);
    await load();
  }
}
