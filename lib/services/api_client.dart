import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../models/service_card.dart';

class PirganjApiClient {
  PirganjApiClient({required this.baseUrl, http.Client? client, this.token})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  String? token;

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
        if (token != null) 'Authorization': 'Bearer $token'
      };

  MediaType _imageType(XFile image) {
    final name = image.name.toLowerCase();
    if (name.endsWith('.png')) return MediaType('image', 'png');
    if (name.endsWith('.webp')) return MediaType('image', 'webp');
    if (name.endsWith('.gif')) return MediaType('image', 'gif');
    if (name.endsWith('.heic')) return MediaType('image', 'heic');
    return MediaType('image', 'jpeg');
  }

  Future<List<ServiceCard>> getServices(
      {String? category, String? search}) async {
    final query = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search
    };
    final json = await _get(
        Uri.parse('$baseUrl/api/services').replace(queryParameters: query));
    return (json['data'] as List<dynamic>)
        .map((item) => ServiceCard.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<dynamic>> getPosts({String? tag}) async {
    final json = await _get(Uri.parse('$baseUrl/api/posts')
        .replace(queryParameters: tag == null ? null : {'tag': tag}));
    return List<dynamic>.from(json['data'] as List);
  }

  Future<List<dynamic>> getComments(String postId) async {
    final json = await _get(Uri.parse('$baseUrl/api/posts/$postId/comments'));
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

  Future<List<dynamic>> getDonors({String? group}) async =>
      _list('/donors', group == null ? null : {'group': group});
  Future<List<dynamic>> getBloodRequests({String? group}) async =>
      _list('/blood-requests', group == null ? null : {'group': group});
  Future<List<dynamic>> getNotices() async => _list('/notices');
  Future<List<dynamic>> getJobs() async => _list('/jobs');
  Future<List<dynamic>> getLostFound() async => _list('/lost-found');
  Future<List<dynamic>> _list(String path, [Map<String, String>? query]) async {
    final json = await _get(
        Uri.parse('$baseUrl/api$path').replace(queryParameters: query));
    return List<dynamic>.from(json['data'] as List);
  }

  Future<Map<String, dynamic>> getOverview() =>
      _get(Uri.parse('$baseUrl/api/overview'));

  Future<List<dynamic>> getNotifications({int limit = 50}) async {
    final json = await _get(Uri.parse('$baseUrl/api/notifications')
        .replace(queryParameters: {'limit': '$limit'}));
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
          {required String phone,
          required String password,
          required String name,
          required String sex,
          required String address}) =>
      _post('/auth/register', {
        'phone': phone,
        'password': password,
        'name': name,
        'sex': sex,
        'address': address
      });
  Future<Map<String, dynamic>> login(
          {required String phone, required String password}) =>
      _post('/auth/login', {'phone': phone, 'password': password});
  Future<Map<String, dynamic>> me() => _get(Uri.parse('$baseUrl/api/auth/me'));
  Future<Map<String, dynamic>> updateProfile(
          {String? name,
          String? sex,
          String? address,
          String? avatarUrl,
          bool clearAvatar = false}) =>
      _put('/auth/me', {
        'name': name,
        'sex': sex,
        'address': address,
        if (avatarUrl != null || clearAvatar) 'avatarUrl': avatarUrl
      });
  Future<void> deleteAccount() async {
    await _delete('/auth/me');
  }

  Future<List<dynamic>> getMyItems() async {
    final json = await _get(Uri.parse('$baseUrl/api/profile/items'));
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
          String phone = ''}) =>
      _post('/lost-found', {
        'title': title,
        'type': type,
        'description': description,
        'location': location,
        'phone': phone
      });
  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await _client.get(uri, headers: _headers);
    return _decode(response);
  }

  Future<Map<String, dynamic>> registerWithImage({
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
      'phone': phone,
      'password': password,
      'name': name,
      'sex': sex,
      'address': address,
    });
    request.files.add(await http.MultipartFile.fromPath(
        'profileImage', profileImage.path,
        filename: profileImage.name, contentType: _imageType(profileImage)));
    return _decode(await http.Response.fromStream(await request.send()));
  }

  Future<Map<String, dynamic>> uploadImage(XFile image,
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
    final response = await _client.post(Uri.parse('$baseUrl/api$path'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _put(
      String path, Map<String, dynamic> body) async {
    final response = await _client.put(Uri.parse('$baseUrl/api$path'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final response =
        await _client.delete(Uri.parse('$baseUrl/api$path'), headers: _headers);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || json['success'] != true)
      throw Exception(
          (json['data'] as Map?)?['message'] ?? 'Pirganj API request failed');
    return json;
  }
}
