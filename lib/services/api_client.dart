import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/service_card.dart';

class PirganjApiClient {
  PirganjApiClient({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  Future<List<ServiceCard>> getServices({String? category, String? search}) async {
    final query = <String, String>{if (category != null && category.isNotEmpty) 'category': category, if (search != null && search.isNotEmpty) 'search': search};
    final json = await _get(Uri.parse('$baseUrl/api/v1/services').replace(queryParameters: query));
    return (json['data'] as List<dynamic>).map((item) => ServiceCard.fromJson(Map<String, dynamic>.from(item))).toList();
  }
  Future<List<dynamic>> getPosts({String? tag}) async { final json = await _get(Uri.parse('$baseUrl/api/v1/posts').replace(queryParameters: tag == null ? null : {'tag': tag})); return List<dynamic>.from(json['data'] as List); }
  Future<List<dynamic>> getDonors() async => _list('/donors');
  Future<List<dynamic>> getBloodRequests() async => _list('/blood-requests');
  Future<List<dynamic>> getNotices() async => _list('/notices');
  Future<List<dynamic>> getJobs() async => _list('/jobs');
  Future<List<dynamic>> getLostFound() async => _list('/lost-found');
  Future<List<dynamic>> _list(String path) async { final json = await _get(Uri.parse('$baseUrl/api/v1$path')); return List<dynamic>.from(json['data'] as List); }
  Future<Map<String, dynamic>> getOverview() => _get(Uri.parse('$baseUrl/api/v1/overview'));
  Future<Map<String, dynamic>> createService({required String name, required String category, String meta = '', String location = '', String phone = '', String openHours = ''}) => _post('/services', {'name': name, 'category': category, 'meta': meta, 'location': location, 'phone': phone, 'openHours': openHours});
  Future<Map<String, dynamic>> createPost({required String author, required String title, required String body, required String tag}) => _post('/posts', {'author': author, 'title': title, 'body': body, 'tag': tag});
  Future<Map<String, dynamic>> createDonor({required String name, required String bloodGroup, required String phone, String area = ''}) => _post('/donors', {'name': name, 'bloodGroup': bloodGroup, 'phone': phone, 'area': area});
  Future<Map<String, dynamic>> createBloodRequest({required String patientName, required String bloodGroup, required String hospital, required String phone, String area = '', String details = '', int units = 1}) => _post('/blood-requests', {'patientName': patientName, 'bloodGroup': bloodGroup, 'hospital': hospital, 'phone': phone, 'area': area, 'details': details, 'units': units});
  Future<Map<String, dynamic>> createNotice({required String title, String body = '', String label = 'কমিউনিটি'}) => _post('/notices', {'title': title, 'body': body, 'label': label});
  Future<Map<String, dynamic>> createJob({required String title, String company = '', String description = '', String location = '', String phone = ''}) => _post('/jobs', {'title': title, 'company': company, 'description': description, 'location': location, 'phone': phone});
  Future<Map<String, dynamic>> createLostFound({required String title, required String type, String description = '', String location = '', String phone = ''}) => _post('/lost-found', {'title': title, 'type': type, 'description': description, 'location': location, 'phone': phone});
  Future<Map<String, dynamic>> _get(Uri uri) async { final response = await _client.get(uri, headers: {'Accept': 'application/json'}); return _decode(response); }
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async { final response = await _client.post(Uri.parse('$baseUrl/api/v1$path'), headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode(body)); return _decode(response); }
  Map<String, dynamic> _decode(http.Response response) { final json = jsonDecode(response.body) as Map<String, dynamic>; if (response.statusCode >= 400 || json['success'] != true) throw Exception(json['data']?['message'] ?? 'Pirganj API request failed'); return json; }
}
