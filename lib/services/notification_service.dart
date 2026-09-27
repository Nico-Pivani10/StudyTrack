import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(
      settings: initializationSettings,
    );
  }

  static Future<void> mostrarProximidad(String lugar) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'studytrack_proximidad',
      'Proximidad',
      channelDescription: 'Notificaciones de proximidad de StudyTrack',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      id: 100,
      title: 'StudyTrack',
      body: 'Estás cerca de $lugar.',
      notificationDetails: notificationDetails,
    );
  }
}