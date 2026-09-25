import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/service_card.dart';

class PirganjApiClient {
  PirganjApiClient({required this.baseUrl, http.Client? client, this.token})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  String? token;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'
      };

  Future<List<ServiceCard>> getServices(
      {String? category, String? search}) async {
    final query = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search
    };
    final json = await _get(
        Uri.parse('$baseUrl/api/v1/services').replace(queryParameters: query));
    return (json['data'] as List<dynamic>)
        .map((item) => ServiceCard.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<dynamic>> getPosts({String? tag}) async {
    final json = await _get(Uri.parse('$baseUrl/api/v1/posts')
        .replace(queryParameters: tag == null ? null : {'tag': tag}));
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
        Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: query));
    return List<dynamic>.from(json['data'] as List);
  }

  Future<Map<String, dynamic>> getOverview() =>
      _get(Uri.parse('$baseUrl/api/v1/overview'));

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
  Future<Map<String, dynamic>> me() =>
      _get(Uri.parse('$baseUrl/api/v1/auth/me'));
  Future<Map<String, dynamic>> updateProfile(
          {String? name, String? sex, String? address}) =>
      _put('/auth/me', {'name': name, 'sex': sex, 'address': address});
  Future<void> deleteAccount() async {
    await _delete('/auth/me');
  }

  Future<List<dynamic>> getMyItems() async {
    final json = await _get(Uri.parse('$baseUrl/api/v1/profile/items'));
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
          required String tag}) =>
      _post('/posts',
          {'author': author, 'title': title, 'body': body, 'tag': tag});
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

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await _client.post(Uri.parse('$baseUrl/api/v1$path'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _put(
      String path, Map<String, dynamic> body) async {
    final response = await _client.put(Uri.parse('$baseUrl/api/v1$path'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final response = await _client.delete(Uri.parse('$baseUrl/api/v1$path'),
        headers: _headers);
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
