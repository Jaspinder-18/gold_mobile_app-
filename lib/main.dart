import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/audio_service.dart';
import 'services/notification_service.dart';
import 'services/socket_service.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF070A12),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  } catch (_) {}

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 3));

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (fcmErr) {
      debugPrint('[Main] FCM background handler note: $fcmErr');
    }
  } catch (fbErr) {
    debugPrint('[Main] Firebase Core init note (continuing smoothly): $fbErr');
  }

  try {
    await AudioService.instance.initialize().timeout(const Duration(seconds: 2));
  } catch (_) {}

  try {
    await BackgroundService.instance.initialize();
  } catch (_) {}

  runApp(const GoldAlertApp());

  Future.microtask(() async {
    try {
      await NotificationService.instance.initialize().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[Main] NotificationService init notice: $e');
    }

    try {
      await SocketService.instance.initialize();
    } catch (_) {}
  });
}

class GoldAlertApp extends StatelessWidget {
  const GoldAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ALERT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070A12),
        primaryColor: const Color(0xFFF59E0B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF59E0B),
          secondary: Color(0xFFFBBF24),
          surface: Color(0xFF0E1626),
        ),
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
    );
  }
}
