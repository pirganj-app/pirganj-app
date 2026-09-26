import 'dart:async';

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
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
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
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: message.data['entityId']?.toString(),
      );
    });
    openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((_) {
      events.add(null);
    });
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
