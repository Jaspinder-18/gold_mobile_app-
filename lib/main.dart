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

  // Set system UI to immersive dark
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

  // Initialize Firebase Core safely without blocking UI
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

  // Fast audio service initialization
  try {
    await AudioService().initialize().timeout(const Duration(seconds: 2));
  } catch (_) {}

  // Launch UI immediately so the user NEVER gets stuck on a black screen!
  runApp(const GoldAlertApp());

  // Spin up asynchronous network and notification services in parallel
  Future.microtask(() async {
    try {
      await NotificationService().initialize().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[Main] NotificationService init notice: $e');
    }

    try {
      await BackgroundService().stopService();
    } catch (_) {}

    try {
      await SocketService().initialize();
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
