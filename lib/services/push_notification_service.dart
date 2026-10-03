import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel pirganjNotificationChannel =
    AndroidNotificationChannel(
  'pirganj_high_importance',
  'Pirganj notifications',
  description: 'Comments, replies, reactions and urgent community updates',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();
  final events = StreamController<void>.broadcast();
  final tapEvents = StreamController<Map<String, String>>.broadcast();
  Map<String, String>? _pendingTap;

  Map<String, String>? takePendingTap() {
    final value = _pendingTap;
    _pendingTap = null;
    return value;
  }

  void _emitTap(Map<String, dynamic> data) {
    final normalized = <String, String>{};
    for (final entry in data.entries) {
      if (entry.value != null && entry.value.toString().isNotEmpty) {
        normalized[entry.key] = entry.value.toString();
      }
    }
    if (normalized.isEmpty) return;
    if (tapEvents.hasListener) {
      tapEvents.add(normalized);
    } else {
      _pendingTap = normalized;
    }
  }

  void _emitLocalTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _emitTap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
  }

  StreamSubscription<String>? tokenSubscription;
  StreamSubscription<RemoteMessage>? messageSubscription;
  StreamSubscription<RemoteMessage>? openedSubscription;

  Future<void> start(PirganjApiClient api) async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(pirganjNotificationChannel);
    await localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_pirganj'),
      ),
      onDidReceiveNotificationResponse: (response) {
        _emitLocalTap(response.payload);
      },
    );
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null) await api.registerPushToken(token);
    await tokenSubscription?.cancel();
    tokenSubscription = messaging.onTokenRefresh.listen((value) async {
      try {
        await api.registerPushToken(value);
      } catch (_) {}
    });
    await messageSubscription?.cancel();
    await openedSubscription?.cancel();
    messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      events.add(null);
      final notification = message.notification;
      if (notification == null) return;
      localNotifications.show(
        id: notification.hashCode,
        title: notification.title ?? 'Pirganj',
        body: notification.body ?? '',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'pirganj_high_importance',
            'Pirganj notifications',
            channelDescription:
                'Comments, replies, reactions and urgent community updates',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_pirganj',
          ),
        ),
        payload: jsonEncode(message.data),
      );
    });
    openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _emitTap(message.data);
      events.add(null);
    });
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) _emitTap(initialMessage.data);
  }

  Future<void> stop(PirganjApiClient api) async {
    try {
      await api.unregisterPushToken();
    } catch (_) {}
    await tokenSubscription?.cancel();
    await messageSubscription?.cancel();
    await openedSubscription?.cancel();
    tokenSubscription = null;
    messageSubscription = null;
    openedSubscription = null;
  }
}
