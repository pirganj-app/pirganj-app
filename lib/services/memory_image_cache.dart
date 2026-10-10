import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class _MemoryImageEntry {
  const _MemoryImageEntry(this.bytes, this.savedAt);

  final Uint8List bytes;
  final DateTime savedAt;
}

/// Session-scoped cache for public carousel and community images.
///
/// Nothing is written to disk. Entries are bounded by total bytes and age,
/// while concurrent requests for the same URL share a single network call.
/// Carousel entries refresh stale bytes in the background; stable community
/// image URLs can opt out of periodic network refreshes.
class MemoryImageCache {
  MemoryImageCache._();

  static final MemoryImageCache instance = MemoryImageCache._();

  static const _ttl = Duration(minutes: 20);
  static const _maxImageBytes = 6 * 1024 * 1024;
  static const _maxCacheBytes = 24 * 1024 * 1024;
  static const _requestTimeout = Duration(seconds: 12);

  final http.Client _client = http.Client();
  final Map<String, _MemoryImageEntry> _entries = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final Map<String, int> _namespaceGenerations = {};
  int _cachedBytes = 0;
  int _generation = 0;

  Future<void> purgeLegacyDiskCache() async {
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      final legacyDirectory = Directory(
          '${temporaryDirectory.path}${Platform.pathSeparator}pirganj_slide_cache');
      if (await legacyDirectory.exists()) {
        await legacyDirectory.delete(recursive: true);
      }
    } catch (_) {
      // The RAM cache remains usable if legacy cleanup is unavailable.
    }
  }

  Future<Uint8List?> getImage(
    String rawUrl, {
    String namespace = 'carousel',
    bool refreshIfExpired = true,
  }) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }

    final key = '$namespace|${uri.toString()}';
    final entry = _entries[key];
    if (entry != null) {
      _touch(key, entry);
      if (!refreshIfExpired ||
          DateTime.now().difference(entry.savedAt) < _ttl) {
        return entry.bytes;
      }
      unawaited(_fetchAndCache(uri,
          key: key, namespace: namespace, stale: entry.bytes));
      return entry.bytes;
    }
    return _fetchAndCache(uri, key: key, namespace: namespace);
  }

  Future<Uint8List?> _fetchAndCache(Uri uri,
      {required String key, required String namespace, Uint8List? stale}) {
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final generation = _generation;
    final namespaceGeneration = _namespaceGenerations[namespace] ?? 0;
    late final Future<Uint8List?> request;
    request = _download(uri).then((bytes) {
      final result = bytes ?? stale;
      if (bytes != null &&
          generation == _generation &&
          namespaceGeneration == (_namespaceGenerations[namespace] ?? 0)) {
        _store(key, bytes);
      }
      return result;
    }).whenComplete(() {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    });
    _inFlight[key] = request;
    return request;
  }

  Future<Uint8List?> _download(Uri uri) async {
    try {
      final response = await _client.get(uri,
          headers: const {'Accept': 'image/*'}).timeout(_requestTimeout);
      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          (contentType != null && !contentType.startsWith('image/')) ||
          response.bodyBytes.isEmpty ||
          response.bodyBytes.length > _maxImageBytes) {
        return null;
      }
      return Uint8List.fromList(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  void _store(String key, Uint8List bytes) {
    final old = _entries.remove(key);
    if (old != null) _cachedBytes -= old.bytes.length;
    _entries[key] = _MemoryImageEntry(bytes, DateTime.now());
    _cachedBytes += bytes.length;

    while (_cachedBytes > _maxCacheBytes && _entries.isNotEmpty) {
      final oldestKey = _entries.keys.first;
      final oldest = _entries.remove(oldestKey)!;
      _cachedBytes -= oldest.bytes.length;
    }
  }

  void _touch(String key, _MemoryImageEntry entry) {
    _entries
      ..remove(key)
      ..[key] = entry;
  }

  void clearNamespace(String namespace) {
    _namespaceGenerations[namespace] =
        (_namespaceGenerations[namespace] ?? 0) + 1;
    final prefix = '$namespace|';
    final keys = _entries.keys.where((key) => key.startsWith(prefix)).toList();
    for (final key in keys) {
      _cachedBytes -= _entries.remove(key)!.bytes.length;
    }
    _inFlight.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Clears cached bytes on logout/session exit; in-flight results are not
  /// allowed to repopulate a cache belonging to the previous active session.
  void clear() {
    _generation++;
    _entries.clear();
    _inFlight.clear();
    _namespaceGenerations.clear();
    _cachedBytes = 0;
  }
}
