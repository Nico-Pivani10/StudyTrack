import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/gps_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  // Necesario antes de inicializar Firebase y plugins.
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Firebase.
  await Firebase.initializeApp();

  // Inicializar las notificaciones locales de StudyTrack.
  await NotificationService.initialize();

  // Solicitar permiso para recibir notificaciones.
  final NotificationSettings settings =
      await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  debugPrint(
    'Permiso notificaciones: ${settings.authorizationStatus}',
  );

  // Obtener token FCM del dispositivo.
  final String? token =
      await FirebaseMessaging.instance.getToken();

  debugPrint('======================================');
  debugPrint('TOKEN FCM:');
  debugPrint(token);
  debugPrint('======================================');

  // Escuchar mensajes de Firebase cuando StudyTrack está abierto.
  FirebaseMessaging.onMessage.listen(
    (RemoteMessage message) {
      debugPrint('======================================');
      debugPrint('NOTIFICACIÓN RECIBIDA');
      debugPrint(
        'Título: ${message.notification?.title}',
      );
      debugPrint(
        'Mensaje: ${message.notification?.body}',
      );
      debugPrint('Datos: ${message.data}');
      debugPrint('======================================');
    },
  );

  // Detectar cuando el usuario toca una notificación
  // y abre StudyTrack.
  FirebaseMessaging.onMessageOpenedApp.listen(
    (RemoteMessage message) {
      debugPrint('======================================');
      debugPrint('NOTIFICACIÓN ABIERTA POR EL USUARIO');
      debugPrint(
        'Título: ${message.notification?.title}',
      );
      debugPrint(
        'Mensaje: ${message.notification?.body}',
      );
      debugPrint('======================================');
    },
  );

  runApp(const StudyTrackApp());
}

class StudyTrackApp extends StatelessWidget {
  const StudyTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'StudyTrack',

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF670310),
        ),

        scaffoldBackgroundColor:
            const Color(0xFFF8F8F8),
      ),

      home: const GpsScreen(),
    );
  }
}