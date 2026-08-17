import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/forum_document.dart';

class CachedLogin {
  const CachedLogin({required this.name, required this.trip});

  final String name;
  final String trip;

  Map<String, String> toJson() => {'name': name, 'trip': trip};

  static CachedLogin? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final trip = value['trip'];
    if (name is! String || trip is! String || name.isEmpty || trip.isEmpty) {
      return null;
    }
    return CachedLogin(name: name, trip: trip);
  }
}

class ReadingMarker {
  const ReadingMarker({
    required this.threadId,
    required this.threadTitle,
    required this.uri,
    required this.floor,
    required this.updatedAt,
  });

  final String threadId;
  final String threadTitle;
  final Uri uri;
  final int floor;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'threadId': threadId,
    'threadTitle': threadTitle,
    'uri': uri.toString(),
    'floor': floor,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static ReadingMarker? fromJson(Object? value) {
    if (value is! Map) return null;
    final threadId = value['threadId'];
    final threadTitle = value['threadTitle'];
    final rawUri = value['uri'];
    final floor = value['floor'];
    final updatedAt = value['updatedAt'];
    if (threadId is! String ||
        threadTitle is! String ||
        rawUri is! String ||
        floor is! num ||
        updatedAt is! String) {
      return null;
    }
    final uri = Uri.tryParse(rawUri);
    final time = DateTime.tryParse(updatedAt);
    if (uri == null || time == null) return null;
    return ReadingMarker(
      threadId: threadId,
      threadTitle: threadTitle,
      uri: uri,
      floor: floor.toInt(),
      updatedAt: time,
    );
  }
}

class FloorBookmark extends ReadingMarker {
  const FloorBookmark({
    required super.threadId,
    required super.threadTitle,
    required super.uri,
    required super.floor,
    required super.updatedAt,
  });

  String get id => '$threadId:$floor';

  static FloorBookmark? fromJson(Object? value) {
    final marker = ReadingMarker.fromJson(value);
    if (marker == null) return null;
    return FloorBookmark(
      threadId: marker.threadId,
      threadTitle: marker.threadTitle,
      uri: marker.uri,
      floor: marker.floor,
      updatedAt: marker.updatedAt,
    );
  }
}

class ReaderStore extends ChangeNotifier {
  static const _progressKey = 'reader.progress.v1';
  static const _bookmarkKey = 'reader.bookmarks.v1';
  static const _scaleKey = 'reader.displayScale.v1';
  static const _loginKey = 'reader.login.v1';

  SharedPreferences? _preferences;
  final Map<String, ReadingMarker> _progress = {};
  final List<FloorBookmark> _bookmarks = [];
  double _displayScale = 1;
  CachedLogin? _login;
  bool _loaded = false;

  bool get loaded => _loaded;
  double get displayScale => _displayScale;
  CachedLogin? get login => _login;
  List<FloorBookmark> get bookmarks => List.unmodifiable(_bookmarks);
  List<ReadingMarker> get openedThreads {
    final result =
        _progress.values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(result);
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      _displayScale = (preferences.getDouble(_scaleKey) ?? 1).clamp(0.3, 1.6);

      final rawLogin = preferences.getString(_loginKey);
      if (rawLogin != null) _login = CachedLogin.fromJson(jsonDecode(rawLogin));

      final rawProgress = preferences.getString(_progressKey);
      if (rawProgress != null) {
        final decoded = jsonDecode(rawProgress);
        if (decoded is List) {
          for (final item in decoded) {
            final marker = ReadingMarker.fromJson(item);
            if (marker != null) _progress[marker.threadId] = marker;
          }
        }
      }

      final rawBookmarks = preferences.getString(_bookmarkKey);
      if (rawBookmarks != null) {
        final decoded = jsonDecode(rawBookmarks);
        if (decoded is List) {
          for (final item in decoded) {
            final bookmark = FloorBookmark.fromJson(item);
            if (bookmark != null) _bookmarks.add(bookmark);
          }
        }
      }
      _sortBookmarks();
    } catch (_) {
      // Persistence is optional during tests and on a temporarily unavailable
      // platform channel. The reader continues with in-memory state.
    }
    _loaded = true;
    notifyListeners();
  }

  ReadingMarker? progressFor(String? threadId) {
    if (threadId == null) return null;
    return _progress[threadId];
  }

  void setDisplayScale(double value) {
    final next = value.clamp(0.3, 1.6);
    if ((next - _displayScale).abs() < 0.001) return;
    _displayScale = next;
    notifyListeners();
    unawaited(_preferences?.setDouble(_scaleKey, next));
  }

  void saveLogin(String name, String trip) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || trip.isEmpty) return;
    _login = CachedLogin(name: normalizedName, trip: trip);
    notifyListeners();
    final preferences = _preferences;
    if (preferences != null) {
      unawaited(preferences.setString(_loginKey, jsonEncode(_login!.toJson())));
    }
  }

  void markThreadOpened(ForumDocument document, int initialFloor) {
    final threadId = document.threadId;
    if (threadId == null || initialFloor < 1) return;
    final previous = _progress[threadId];
    _progress[threadId] = ReadingMarker(
      threadId: threadId,
      threadTitle: document.title,
      uri: previous?.uri ?? _uriForFloor(document, initialFloor),
      floor: previous?.floor ?? initialFloor,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    _saveProgress();
  }

  void recordProgress(ForumDocument document, int floor) {
    final threadId = document.threadId;
    if (threadId == null || floor < 1) return;
    final previous = _progress[threadId];
    if (previous != null && previous.floor >= floor) return;
    _progress[threadId] = ReadingMarker(
      threadId: threadId,
      threadTitle: document.title,
      uri: _uriForFloor(document, floor),
      floor: floor,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    _saveProgress();
  }

  bool addBookmark(ForumDocument document, int floor) {
    final threadId = document.threadId;
    if (threadId == null || floor < 1) return false;
    final id = '$threadId:$floor';
    if (_bookmarks.any((item) => item.id == id)) return false;
    _bookmarks.add(
      FloorBookmark(
        threadId: threadId,
        threadTitle: document.title,
        uri: _uriForFloor(document, floor),
        floor: floor,
        updatedAt: DateTime.now(),
      ),
    );
    _sortBookmarks();
    notifyListeners();
    _saveBookmarks();
    return true;
  }

  void removeBookmark(String id) {
    final oldLength = _bookmarks.length;
    _bookmarks.removeWhere((item) => item.id == id);
    if (_bookmarks.length == oldLength) return;
    notifyListeners();
    _saveBookmarks();
  }

  Uri _uriForFloor(ForumDocument document, int floor) {
    final threadId = document.threadId!;
    final page = ((floor - 1) ~/ 50) + 1;
    return document.uri.replace(
      path: '/view/$threadId-$page',
      query: null,
      fragment: null,
    );
  }

  void _sortBookmarks() {
    _bookmarks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _saveProgress() {
    final preferences = _preferences;
    if (preferences == null) return;
    unawaited(
      preferences.setString(
        _progressKey,
        jsonEncode(_progress.values.map((item) => item.toJson()).toList()),
      ),
    );
  }

  void _saveBookmarks() {
    final preferences = _preferences;
    if (preferences == null) return;
    unawaited(
      preferences.setString(
        _bookmarkKey,
        jsonEncode(_bookmarks.map((item) => item.toJson()).toList()),
      ),
    );
  }
}
