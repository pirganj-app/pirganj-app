import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DiskImageCache {
  DiskImageCache._();

  static final DiskImageCache instance = DiskImageCache._();

  static const _cacheTtl = Duration(days: 1);
  static const _requestTimeout = Duration(seconds: 12);
  static const _maxImageBytes = 6 * 1024 * 1024;
  static const _maxCacheBytes = 32 * 1024 * 1024;

  final http.Client _client = http.Client();
  final Map<String, Future<File?>> _inFlight = {};
  final Set<String> _refreshing = {};
  Future<Directory>? _directoryFuture;

  Future<File?> getImage(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return Future<File?>.value(null);
    }

    final key = uri.toString();
    final pending = _inFlight[key];
    if (pending != null) return pending;

    late final Future<File?> request;
    request = _load(uri).whenComplete(() {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    });
    _inFlight[key] = request;
    return request;
  }

  Future<File?> _load(Uri uri) async {
    Directory directory;
    try {
      directory = await (_directoryFuture ??= _createDirectory());
    } catch (_) {
      _directoryFuture = null;
      return null;
    }

    final file = File(
        '${directory.path}${Platform.pathSeparator}${_cacheKey(uri.toString())}.img');
    File? staleFile;
    try {
      if (await file.exists()) {
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file && stat.size > 0) {
          staleFile = file;
          if (DateTime.now().difference(stat.modified) <= _cacheTtl) {
            return file;
          }
        } else {
          await file.delete();
        }
      }
    } catch (_) {
      staleFile = null;
    }

    if (staleFile != null) {
      _refreshStale(uri, file, directory, staleFile);
      return staleFile;
    }
    return _download(uri, file, directory, null);
  }

  void _refreshStale(Uri uri, File file, Directory directory, File staleFile) {
    final key = uri.toString();
    if (!_refreshing.add(key)) return;
    unawaited(() async {
      try {
        await _download(uri, file, directory, staleFile);
      } finally {
        _refreshing.remove(key);
      }
    }());
  }

  Future<File?> _download(
      Uri uri, File file, Directory directory, File? fallback) async {
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
        return fallback;
      }

      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsBytes(response.bodyBytes, flush: true);
      if (await file.exists()) await file.delete();
      final savedFile = await tempFile.rename(file.path);
      await _trimCache(directory, savedFile.path);
      return savedFile;
    } catch (_) {
      return fallback;
    }
  }

  Future<Directory> _createDirectory() async {
    final temporaryDirectory = await getTemporaryDirectory();
    final cacheDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}pirganj_slide_cache');
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }
    return cacheDirectory;
  }

  Future<void> _trimCache(Directory directory, String keepPath) async {
    final entries = <_CacheFileInfo>[];
    var totalBytes = 0;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || entity.path.endsWith('.tmp')) continue;
        final stat = await entity.stat();
        totalBytes += stat.size;
        entries.add(_CacheFileInfo(entity, stat.size, stat.modified));
      }
    } catch (_) {
      return;
    }

    if (totalBytes <= _maxCacheBytes) return;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (totalBytes <= _maxCacheBytes) break;
      if (entry.file.path == keepPath) continue;
      try {
        await entry.file.delete();
        totalBytes -= entry.size;
      } catch (_) {}
    }
  }

  String _cacheKey(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _CacheFileInfo {
  const _CacheFileInfo(this.file, this.size, this.modified);
  final File file;
  final int size;
  final DateTime modified;
}
