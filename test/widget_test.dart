import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pirganj/main.dart';
import 'package:pirganj/services/api_client.dart';

class MockClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request.url.path.endsWith('/posts')
        ? {'success': true, 'data': []}
        : request.url.path.endsWith('/donors')
            ? {'success': true, 'data': [{'name': 'শাহেদ', 'group': 'O+', 'area': 'পীরগঞ্জ', 'phone': '01700000000'}]}
            : {
            'success': true,
            'data': [
              {'id': 'test', 'name': 'টেস্ট হাসপাতাল', 'category': 'হাসপাতাল', 'meta': '', 'location': 'পীরগঞ্জ', 'phone': '', 'open': 'এখন খোলা', 'icon': '+'}
            ]
            };
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(Stream.fromIterable([bytes]), 200, contentLength: bytes.length, request: request);
  }
}

void main() {
  testWidgets('Pirganj home screen opens and renders popular services', (tester) async {
    final api = PirganjApiClient(baseUrl: 'https://test.local', client: MockClient());
    await tester.pumpWidget(PirganjAppWithApi(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Pirganj'), findsOneWidget);
    expect(find.text('জনপ্রিয় সেবা'), findsOneWidget);
    expect(find.text('হাসপাতাল'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Emergency topic page renders add action and topic chips', (tester) async {
    final api = PirganjApiClient(baseUrl: 'https://test.local', client: MockClient());
    await tester.pumpWidget(MaterialApp(home: EmergencyPage(api: api)));
    await tester.pump();
    expect(find.text('জরুরি সেবা'), findsOneWidget);
    expect(find.text('রক্তদাতা'), findsOneWidget);
    expect(find.text('রক্তের অনুরোধ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Category detail page renders count, cards and add action', (tester) async {
    final api = PirganjApiClient(baseUrl: 'https://test.local', client: MockClient());
    await tester.pumpWidget(MaterialApp(home: ServiceCategoryPage(api: api, category: 'হাসপাতাল', title: 'হাসপাতাল', icon: Icons.local_hospital)));
    await tester.pumpAndSettle();
    expect(find.text('হাসপাতাল'), findsOneWidget);
    expect(find.text('1টি তথ্য'), findsOneWidget);
    expect(find.text('নতুন তথ্য'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Blood topic page renders only donor data cards', (tester) async {
    final api = PirganjApiClient(baseUrl: 'https://test.local', client: MockClient());
    await tester.pumpWidget(MaterialApp(home: TopicDataPage(api: api, topic: 0)));
    await tester.pumpAndSettle();
    expect(find.text('রক্তদাতা'), findsOneWidget);
    expect(find.text('রক্তের অনুরোধ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class PirganjAppWithApi extends StatelessWidget {
  const PirganjAppWithApi({super.key, required this.api});
  final PirganjApiClient api;
  @override
  Widget build(context) => MaterialApp(theme: ThemeData(useMaterial3: true), home: HomeScreen(api: api));
}
