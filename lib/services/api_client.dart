import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/service_card.dart';

class _GetCacheEntry {
  const _GetCacheEntry(this.future, this.expiresAt);
  final Future<Map<String, dynamic>> future;
  final DateTime expiresAt;
}

class PirganjApiClient {
  PirganjApiClient({required this.baseUrl, http.Client? client, this.token})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  String? token;
  String? deviceId;
  Future<void> Function()? onUnauthorized;
  final Map<String, Future<List<ServiceCard>>> _serviceCache = {};
  final Map<String, DateTime> _serviceCacheAt = {};
  final Map<String, Future<List<ServiceCard>>> _serviceInFlight = {};
  final Map<String, Future<Map<String, dynamic>>> _publicProfileCache = {};
  final Map<String, DateTime> _publicProfileCacheAt = {};
  final Map<String, Future<Map<String, dynamic>>> _publicProfileInFlight = {};
  final Map<String, _GetCacheEntry> _readCache = {};
  final Map<String, Future<Map<String, dynamic>>> _getInFlight = {};
  static const _maxServiceCacheEntries = 64;
  static const _maxPublicProfileCacheEntries = 64;
  static const _maxReadCacheEntries = 64;
  static const _serviceCacheTtl = Duration(minutes: 1);
  static const _publicProfileCacheTtl = Duration(seconds: 45);
  static const _myItemsCacheTtl = Duration(minutes: 1);
  static const _catalogCacheTtl = Duration(seconds: 25);
  static const _requestTimeout = Duration(seconds: 10);
  static const _maxGetAttempts = 2;
  static const _imageBucket = 'pirganj-images';
  int _cacheGeneration = 0;

  void _trimCache<K, V>(Map<K, V> cache, int maximum,
      {void Function(K key)? onRemove}) {
    while (cache.length > maximum) {
      final key = cache.keys.first;
      cache.remove(key);
      onRemove?.call(key);
    }
  }

  String? get userId {
    try {
      if (token == null) return null;
      final parts = token!.split('.');
      if (parts.length != 3) return null;
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return (jsonDecode(payload) as Map<String, dynamic>)['sub']?.toString();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (deviceId != null && deviceId!.isNotEmpty) 'X-Device-Id': deviceId!,
        if (token != null) 'Authorization': 'Bearer $token'
      };

  Future<Map<String, dynamic>> getVersion() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/version'), headers: _headers)
        .timeout(_requestTimeout);
    return _decode(response);
  }

  Future<bool> hasInternetConnection() async {
    try {
      final addresses = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      return addresses.isNotEmpty && addresses.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    if (token != null) {
      try {
        await _post('/auth/logout', const {});
      } catch (_) {
        // Local logout must still complete if the network is unavailable.
      }
    }
    await clearSessionCaches();
  }

  Future<void> clearSessionCaches() async {
    clearRamCaches();
  }

  void clearRamCaches() {
    _cacheGeneration++;
    _serviceCache.clear();
    _serviceCacheAt.clear();
    _serviceInFlight.clear();
    _publicProfileCache.clear();
    _publicProfileCacheAt.clear();
    _publicProfileInFlight.clear();
    _readCache.clear();
    _getInFlight.clear();
  }

  Future<void> logPageVisit(String pageName) async {
    if (token == null || pageName.trim().isEmpty) return;
    try {
      await _post('/activity/page', {'pageName': pageName.trim()});
    } catch (_) {
      // Page auditing is detached from normal app navigation.
    }
  }

  Future<Map<String, dynamic>?> getAppOpenMessage() async {
    final json = await _get(Uri.parse('$baseUrl/api/app-open-message'),
        cacheFor: _catalogCacheTtl);
    final data = json['data'];
    if (data is! Map || data['visible'] != true) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<String> getAboutHtml() async {
    final json =
        await _get(Uri.parse('$baseUrl/api/about'), cacheFor: _catalogCacheTtl);
    return (json['data'] as Map?)?['html']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> getPublicProfile(String userId,
      {bool forceRefresh = false}) {
    final pending = _publicProfileInFlight[userId];
    if (pending != null) return pending;
    final cached = _publicProfileCache[userId];
    final cachedAt = _publicProfileCacheAt[userId];
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _publicProfileCacheTtl) {
      _publicProfileCache
        ..remove(userId)
        ..[userId] = cached;
      return cached;
    }
    _publicProfileCache.remove(userId);
    _publicProfileCacheAt.remove(userId);
    late final Future<Map<String, dynamic>> request;
    request = (() async {
      try {
        final json = await _get(Uri.parse('$baseUrl/api/users/$userId/public'));
        return Map<String, dynamic>.from(json['data'] as Map);
      } catch (_) {
        if (identical(_publicProfileCache[userId], request)) {
          _publicProfileCache.remove(userId);
          _publicProfileCacheAt.remove(userId);
        }
        rethrow;
      }
    })()
        .whenComplete(() {
      if (identical(_publicProfileInFlight[userId], request)) {
        _publicProfileInFlight.remove(userId);
      }
    });
    _publicProfileInFlight[userId] = request;
    _publicProfileCache[userId] = request;
    _publicProfileCacheAt[userId] = DateTime.now();
    _trimCache(_publicProfileCache, _maxPublicProfileCacheEntries,
        onRemove: _publicProfileCacheAt.remove);
    return request;
  }

  MediaType _imageType(XFile image) {
    final name = image.name.toLowerCase();
    if (name.endsWith('.png')) return MediaType('image', 'png');
    if (name.endsWith('.webp')) return MediaType('image', 'webp');
    if (name.endsWith('.gif')) return MediaType('image', 'gif');
    if (name.endsWith('.heic')) return MediaType('image', 'heic');
    return MediaType('image', 'jpeg');
  }

  Future<List<ServiceCard>> getServices(
      {String? category,
      String? search,
      int limit = 20,
      int offset = 0,
      bool forceRefresh = false}) {
    final key = '${category ?? ''}|${search ?? ''}|$limit|$offset';
    final pending = _serviceInFlight[key];
    if (pending != null) return pending;
    final cached = _serviceCache[key];
    final cachedAt = _serviceCacheAt[key];
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _serviceCacheTtl) {
      _serviceCache
        ..remove(key)
        ..[key] = cached;
      return cached;
    }
    _serviceCache.remove(key);
    _serviceCacheAt.remove(key);
    late final Future<List<ServiceCard>> request;
    request = (() async {
      try {
        final query = <String, String>{
          if (category != null && category.isNotEmpty) 'category': category,
          if (search != null && search.isNotEmpty) 'search': search,
          'limit': '$limit',
          'offset': '$offset',
        };
        final json = await _get(
            Uri.parse('$baseUrl/api/services').replace(queryParameters: query));
        return (json['data'] as List<dynamic>)
            .map(
                (item) => ServiceCard.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      } catch (error) {
        if (identical(_serviceCache[key], request)) {
          _serviceCache.remove(key);
          _serviceCacheAt.remove(key);
        }
        rethrow;
      }
    })()
        .whenComplete(() {
      if (identical(_serviceInFlight[key], request)) {
        _serviceInFlight.remove(key);
      }
    });
    _serviceCache[key] = request;
    _serviceCacheAt[key] = DateTime.now();
    _serviceInFlight[key] = request;
    _trimCache(_serviceCache, _maxServiceCacheEntries,
        onRemove: _serviceCacheAt.remove);
    return request;
  }

  void clearServiceCache() {
    _serviceCache.clear();
    _serviceCacheAt.clear();
    _serviceInFlight.clear();
  }

  Future<List<dynamic>> getPosts(
      {String? tag, int limit = 20, int offset = 0, String? before}) async {
    final json =
        await _get(Uri.parse('$baseUrl/api/posts').replace(queryParameters: {
      if (tag != null) 'tag': tag,
      'limit': '$limit',
      'offset': '$offset',
      if (before != null && before.isNotEmpty) 'before': before,
    }));
    return List<dynamic>.from(json['data'] as List);
  }

  Future<Map<String, dynamic>> getPost(String postId) async {
    final json = await _get(Uri.parse('$baseUrl/api/posts/$postId'));
    return Map<String, dynamic>.from(json['data'] as Map);
  }

  Future<List<dynamic>> getComments(String postId,
      {int limit = 50, int offset = 0}) async {
    final json = await _get(Uri.parse('$baseUrl/api/posts/$postId/comments')
        .replace(queryParameters: {'limit': '$limit', 'offset': '$offset'}));
    return List<dynamic>.from(json['data'] as List);
  }

  Future<Map<String, dynamic>> addComment(String postId,
          {required String body, String? parentId}) =>
      _post('/posts/$postId/comments',
          {'body': body, if (parentId != null) 'parentId': parentId});
  Future<Map<String, dynamic>> updateComment(String id, String body) =>
      _put('/comments/$id', {'body': body});
  Future<void> deleteComment(String id) async {
    await _delete('/comments/$id');
  }

  Future<List<dynamic>> togglePostReaction(String postId,
      {String reaction = 'like'}) async {
    final json =
        await _post('/posts/$postId/reactions', {'reaction': reaction});
    return List<dynamic>.from(json['data'] as List);
  }

  Future<List<dynamic>> getPostReactions(String postId) async {
    final json = await _get(Uri.parse('$baseUrl/api/posts/$postId/reactions'));
    return List<dynamic>.from(json['data'] as List);
  }

  Future<List<dynamic>> toggleCommentReaction(String commentId,
      {String reaction = 'like'}) async {
    final json =
        await _post('/comments/$commentId/reactions', {'reaction': reaction});
    return List<dynamic>.from(json['data'] as List);
  }

  Future<List<dynamic>> getCommentReactions(String commentId) async {
    final json =
        await _get(Uri.parse('$baseUrl/api/comments/$commentId/reactions'));
    return List<dynamic>.from(json['data'] as List);
  }

  Future<List<dynamic>> getDonors(
      {String? group,
      int limit = 20,
      int offset = 0,
      bool forceRefresh = false}) async {
    final query = {
      'limit': '$limit',
      'offset': '$offset',
      if (group != null) 'group': group
    };
    return _list('/donors', query, forceRefresh: forceRefresh);
  }

  Future<List<dynamic>> getBloodRequests(
      {String? group,
      int limit = 20,
      int offset = 0,
      bool forceRefresh = false}) async {
    final query = {
      'limit': '$limit',
      'offset': '$offset',
      if (group != null) 'group': group
    };
    return _list('/blood-requests', query, forceRefresh: forceRefresh);
  }

  Future<List<dynamic>> getNotices(
          {int limit = 20, int offset = 0, bool forceRefresh = false}) async =>
      _list('/notices', {'limit': '$limit', 'offset': '$offset'},
          forceRefresh: forceRefresh);
  Future<List<dynamic>> getJobs(
          {int limit = 20, int offset = 0, bool forceRefresh = false}) async =>
      _list('/jobs', {'limit': '$limit', 'offset': '$offset'},
          forceRefresh: forceRefresh);
  Future<List<dynamic>> getLostFound(
          {int limit = 20, int offset = 0, bool forceRefresh = false}) async =>
      _list('/lost-found', {'limit': '$limit', 'offset': '$offset'},
          forceRefresh: forceRefresh);
  Future<List<dynamic>> _list(String path, Map<String, String> query,
      {bool forceRefresh = false}) async {
    final json = await _get(
      Uri.parse('$baseUrl/api$path').replace(queryParameters: query),
      cacheFor: _catalogCacheTtl,
      forceRefresh: forceRefresh,
    );
    return List<dynamic>.from(json['data'] as List);
  }

  Future<Map<String, dynamic>> getOverview() =>
      _get(Uri.parse('$baseUrl/api/overview'), cacheFor: _catalogCacheTtl);

  Future<List<dynamic>> getNotifications(
      {int limit = 50, int offset = 0}) async {
    final json = await _get(Uri.parse('$baseUrl/api/notifications')
        .replace(queryParameters: {'limit': '$limit', 'offset': '$offset'}));
    return List<dynamic>.from(json['data'] as List);
  }

  Future<int> getUnreadNotificationCount() async {
    final json =
        await _get(Uri.parse('$baseUrl/api/notifications/unread-count'));
    return ((json['data'] as Map?)?['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead(String id) async {
    await _put('/notifications/$id/read', {});
  }

  Future<void> markAllNotificationsRead() async {
    await _put('/notifications/read-all', {});
  }

  Future<void> deleteNotification(String id) async {
    await _delete('/notifications/$id');
  }

  Future<void> deleteAllNotifications() async {
    await _delete('/notifications');
  }

  Future<void> registerPushToken(String token,
      {String platform = 'android'}) async {
    await _post('/devices/push-token', {'token': token, 'platform': platform});
  }

  Future<void> unregisterPushToken() async {
    await _delete('/devices/push-token');
  }

  Future<Map<String, dynamic>> register(
          {required String email,
          required String phone,
          required String password,
          required String name,
          required String sex,
          required String address}) =>
      _post('/auth/register', {
        'email': email,
        'phone': phone,
        'password': password,
        'name': name,
        'sex': sex,
        'address': address
      });
  Future<Map<String, dynamic>> login(
          {required String email, required String password}) =>
      _post('/auth/login', {'email': email, 'password': password});
  Future<Map<String, dynamic>> loginWithGoogle(String accessToken) =>
      _post('/auth/google', {'accessToken': accessToken});
  Future<Map<String, dynamic>> completeGoogleRegistration({
    required String accessToken,
    required String email,
    required String phone,
    required String password,
    required String name,
    required String sex,
    required String address,
    XFile? profileImage,
  }) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/api/auth/google/register'));
    request.headers.addAll(_headers);
    request.fields.addAll({
      'accessToken': accessToken,
      'email': email,
      'phone': phone,
      'password': password,
      'name': name,
      'sex': sex,
      'address': address,
    });
    if (profileImage != null) {
      request.files.add(await http.MultipartFile.fromPath(
          'profileImage', profileImage.path,
          filename: profileImage.name, contentType: _imageType(profileImage)));
    }
    return _decode(await http.Response.fromStream(
        await request.send().timeout(_requestTimeout)));
  }

  Future<Map<String, dynamic>> me() => _get(Uri.parse('$baseUrl/api/auth/me'));
  Future<Map<String, dynamic>> updateProfile(
      {String? name,
      String? sex,
      String? address,
      String? avatarUrl,
      bool clearAvatar = false,
      bool? profileLocked}) async {
    final response = await _put('/auth/me', {
      if (name != null) 'name': name,
      if (sex != null) 'sex': sex,
      if (address != null) 'address': address,
      if (profileLocked != null) 'profileLocked': profileLocked,
      if (avatarUrl != null || clearAvatar) 'avatarUrl': avatarUrl
    });
    if (profileLocked != null) {
      final user = (response['data'] as Map?)?['user'] as Map?;
      final saved =
          user?['profileLocked'] == true || user?['profile_locked'] == true;
      if (saved != profileLocked) {
        throw Exception('Profile lock save হয়নি');
      }
    }
    return response;
  }

  Future<void> deleteAccount() async {
    await _delete('/auth/me');
  }

  Future<List<dynamic>> getMyItems(
      {int limit = 100,
      int offset = 0,
      String? resource,
      bool forceRefresh = false}) async {
    final json = await _get(
        Uri.parse('$baseUrl/api/profile/items').replace(queryParameters: {
          'limit': '$limit',
          'offset': '$offset',
          if (resource != null) 'resource': resource,
        }),
        cacheFor: _myItemsCacheTtl,
        forceRefresh: forceRefresh);
    return List<dynamic>.from(json['data'] as List);
  }

  Future<Map<String, dynamic>> updateItem(
          String resource, String id, Map<String, dynamic> data) =>
      _put('/profile/items/$resource/$id', data);
  Future<void> deleteItem(String resource, String id) async {
    await _delete('/profile/items/$resource/$id');
  }

  Future<Map<String, dynamic>> createService(
          {required String name,
          required String category,
          String meta = '',
          String location = '',
          String phone = '',
          String openHours = ''}) =>
      _post('/services', {
        'name': name,
        'category': category,
        'meta': meta,
        'location': location,
        'phone': phone,
        'openHours': openHours
      });
  Future<Map<String, dynamic>> createPost(
          {required String author,
          required String title,
          required String body,
          required String tag,
          String? imageUrl}) =>
      _post('/posts', {
        'author': author,
        'title': title,
        'body': body,
        'tag': tag,
        if (imageUrl != null) 'imageUrl': imageUrl
      });
  Future<Map<String, dynamic>> createDonor(
          {required String name,
          required String bloodGroup,
          required String phone,
          String area = ''}) =>
      _post('/donors', {
        'name': name,
        'bloodGroup': bloodGroup,
        'phone': phone,
        'area': area
      });
  Future<Map<String, dynamic>> createBloodRequest(
          {required String patientName,
          required String bloodGroup,
          required String hospital,
          required String phone,
          String area = '',
          String details = '',
          int units = 1}) =>
      _post('/blood-requests', {
        'patientName': patientName,
        'bloodGroup': bloodGroup,
        'hospital': hospital,
        'phone': phone,
        'area': area,
        'details': details,
        'units': units
      });
  Future<Map<String, dynamic>> createNotice(
          {required String title,
          String body = '',
          String label = 'কমিউনিটি'}) =>
      _post('/notices', {'title': title, 'body': body, 'label': label});
  Future<Map<String, dynamic>> createJob(
          {required String title,
          String company = '',
          String description = '',
          String location = '',
          String phone = ''}) =>
      _post('/jobs', {
        'title': title,
        'company': company,
        'description': description,
        'location': location,
        'phone': phone
      });
  Future<Map<String, dynamic>> createLostFound(
          {required String title,
          required String type,
          String description = '',
          String location = '',
          String phone = '',
          String? imageUrl}) =>
      _post('/lost-found', {
        'title': title,
        'type': type,
        'description': description,
        'location': location,
        'phone': phone,
        if (imageUrl != null) 'imageUrl': imageUrl
      });
  Future<Map<String, dynamic>> _get(Uri uri,
      {Duration? cacheFor, bool forceRefresh = false}) async {
    final cacheKey = '${userId ?? 'anonymous'}|${uri.toString()}';
    final pending = _getInFlight[cacheKey];
    if (pending != null) return pending;

    final now = DateTime.now();
    final shouldCache = cacheFor != null && cacheFor > Duration.zero;
    final cached = shouldCache ? _readCache[cacheKey] : null;
    if (!forceRefresh && cached != null && now.isBefore(cached.expiresAt)) {
      _readCache
        ..remove(cacheKey)
        ..[cacheKey] = cached;
      return cached.future;
    }
    if (forceRefresh || cached != null) _readCache.remove(cacheKey);

    final generation = _cacheGeneration;
    late final Future<Map<String, dynamic>> request;
    request = _fetchGet(uri).whenComplete(() {
      if (identical(_getInFlight[cacheKey], request)) {
        _getInFlight.remove(cacheKey);
      }
    });
    _getInFlight[cacheKey] = request;
    try {
      final result = await request;
      if (shouldCache && generation == _cacheGeneration) {
        _readCache[cacheKey] = _GetCacheEntry(
            Future<Map<String, dynamic>>.value(result),
            DateTime.now().add(cacheFor));
        _trimCache(_readCache, _maxReadCacheEntries);
      }
      return result;
    } finally {
      if (identical(_getInFlight[cacheKey], request)) {
        _getInFlight.remove(cacheKey);
      }
    }
  }

  Future<Map<String, dynamic>> _fetchGet(Uri uri) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxGetAttempts; attempt++) {
      try {
        final response =
            await _client.get(uri, headers: _headers).timeout(_requestTimeout);
        if (response.statusCode >= 500 && attempt < _maxGetAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        return _decode(response);
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      }
      if (attempt < _maxGetAttempts) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw lastError ?? const HttpException('Network request failed');
  }

  Future<Map<String, dynamic>> registerWithImage({
    required String email,
    required String phone,
    required String password,
    required String name,
    required String sex,
    required String address,
    required XFile profileImage,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/auth/register'));
    request.headers.addAll(_headers);
    request.fields.addAll({
      'email': email,
      'phone': phone,
      'password': password,
      'name': name,
      'sex': sex,
      'address': address,
    });
    request.files.add(await http.MultipartFile.fromPath(
        'profileImage', profileImage.path,
        filename: profileImage.name, contentType: _imageType(profileImage)));
    return _decode(await http.Response.fromStream(
        await request.send().timeout(_requestTimeout)));
  }

  Future<Map<String, dynamic>> uploadImage(XFile image,
      {required String kind}) async {
    final optimized = await _optimizeImage(image);
    try {
      final mimeType = optimized.mimeType ?? 'image/webp';
      final signedResponse = await _post('/uploads/signed', {
        'kind': kind,
        'mimeType': mimeType,
        'fileName': optimized.name,
      });
      final signed = Map<String, dynamic>.from(signedResponse['data'] as Map);
      await Supabase.instance.client.storage
          .from(_imageBucket)
          .uploadToSignedUrl(
            signed['path'].toString(),
            signed['token'].toString(),
            File(optimized.path),
            FileOptions(
                contentType: mimeType, upsert: false, cacheControl: '31536000'),
          );
      return {
        'success': true,
        'data': {'path': signed['path'], 'url': signed['url']}
      };
    } catch (_) {
      return _uploadImageMultipart(optimized, kind: kind);
    }
  }

  Future<XFile> _optimizeImage(XFile image) async {
    try {
      final directory = await getTemporaryDirectory();
      final target =
          '${directory.path}/pirganj_${DateTime.now().microsecondsSinceEpoch}.webp';
      final compressed = await FlutterImageCompress.compressWithFile(
        image.path,
        minWidth: 1280,
        minHeight: 1280,
        quality: 82,
        format: CompressFormat.webp,
      );
      if (compressed == null || compressed.isEmpty) return image;
      final file = await File(target).writeAsBytes(compressed, flush: true);
      return XFile(file.path, name: 'upload.webp', mimeType: 'image/webp');
    } catch (_) {
      return image;
    }
  }

  Future<Map<String, dynamic>> _uploadImageMultipart(XFile image,
      {required String kind}) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/uploads/image'));
    request.headers.addAll(_headers);
    request.fields['kind'] = kind;
    request.files.add(await http.MultipartFile.fromPath('image', image.path,
        filename: image.name, contentType: _imageType(image)));
    return _decode(await http.Response.fromStream(await request.send()));
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(Uri.parse('$baseUrl/api$path'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(_requestTimeout);
    final result = _decode(response);
    _invalidateAfterMutation(path);
    return result;
  }

  Future<Map<String, dynamic>> _put(
      String path, Map<String, dynamic> body) async {
    final response = await _client
        .put(Uri.parse('$baseUrl/api$path'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(_requestTimeout);
    final result = _decode(response);
    _invalidateAfterMutation(path);
    return result;
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final response = await _client
        .delete(Uri.parse('$baseUrl/api$path'), headers: _headers)
        .timeout(_requestTimeout);
    final result = _decode(response);
    _invalidateAfterMutation(path);
    return result;
  }

  void _invalidateAfterMutation(String path) {
    if (path.startsWith('/activity/') ||
        path.startsWith('/notifications') ||
        path.startsWith('/devices/')) {
      return;
    }

    _cacheGeneration++;
    _readCache.clear();
    _getInFlight.clear();
    final affectsServices = path.startsWith('/services') ||
        path.startsWith('/profile/items/services');
    if (affectsServices) {
      clearServiceCache();
    }

    final isContentMutation = (path.startsWith('/services') ||
            path.startsWith('/posts') ||
            path.startsWith('/donors') ||
            path.startsWith('/blood-requests') ||
            path.startsWith('/notices') ||
            path.startsWith('/jobs') ||
            path.startsWith('/lost-found') ||
            path.startsWith('/profile/items/')) &&
        !path.contains('/comments') &&
        !path.contains('/reactions');
    if (isContentMutation ||
        path.startsWith('/auth/me') ||
        path.startsWith('/profile/items/')) {
      _publicProfileCache.clear();
      _publicProfileCacheAt.clear();
      _publicProfileInFlight.clear();
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Invalid API envelope');
      }
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw HttpException(
          'Server returned an invalid response (${response.statusCode})');
    }
    if (response.statusCode == 401 && token != null) {
      final handler = onUnauthorized;
      if (handler != null) unawaited(handler());
    }
    if (response.statusCode >= 400 || json['success'] != true) {
      final message = (json['data'] as Map?)?['message']?.toString();
      throw Exception(message == null || message.isEmpty
          ? 'কাজটি সম্পন্ন করা যায়নি। আবার চেষ্টা করুন।'
          : message);
    }
    return json;
  }
}
