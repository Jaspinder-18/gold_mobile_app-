import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/market_data.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Function(AlertEvent)? onNotificationTap;

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Notification payload contains screenshot event data
        if (response.payload != null && onNotificationTap != null) {
          // Payload handled by app
        }
      },
    );

    // Create High-Priority Alert Notification Channel
    const androidChannel = AndroidNotificationChannel(
      'gold_alerts_channel',
      'Gold Level Alerts',
      description: 'Loud alarm clock notifications for Gold (XAU/USD) level touches',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> showAlertNotification(AlertEvent event) async {
    final isResistance = event.level.startsWith('R');
    final title = '🚨 GOLD TOUCHED ${event.level} @ \$${event.currentPrice.toStringAsFixed(2)}';
    final body = 'Target: \$${event.levelPrice.toStringAsFixed(2)} · ${isResistance ? "Resistance" : "Support"} Level · Tap to view full TradingView chart';

    final androidDetails = AndroidNotificationDetails(
      'gold_alerts_channel',
      'Gold Level Alerts',
      channelDescription: 'Loud alarm clock notifications for Gold level touches',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Gold Level Alert',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'XAU/USD Alert Terminal',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: event.screenshotPath,
    );
  }
}
