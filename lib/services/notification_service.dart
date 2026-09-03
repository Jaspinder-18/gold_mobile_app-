import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/market_data.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Function(String?)? onNotificationTap;
  bool _isInitialized = false;
  bool _hasPermission = false;

  bool get hasPermission => _hasPermission;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (onNotificationTap != null) {
          try {
            onNotificationTap?.call(response.payload);
          } catch (e) {
            debugPrint('[NotificationService] onNotificationTap error: $e');
          }
        }
      },
    );

    // Create Loud Alarm Notification Channel with raw resource sound
    final androidChannel = AndroidNotificationChannel(
      'gold_alarm_channel_v3',
      '🚨 High Priority Price Level Alarms',
      description: 'Loud alarm clock sound & high priority notifications for market level touches',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm_clock'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      enableLights: true,
      showBadge: true,
    );

    final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(androidChannel);
    }

    _isInitialized = true;
  }

  /// Request runtime permissions on Android 13+ (API 33+) & iOS
  /// Call this when the UI is mounted so the system dialog can display properly
  Future<bool> requestPermissions() async {
    try {
      final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final granted = await androidImpl.requestNotificationsPermission();
        _hasPermission = granted ?? false;
        return _hasPermission;
      }

      final iosImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosImpl != null) {
        final granted = await iosImpl.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        _hasPermission = granted ?? false;
        return _hasPermission;
      }
    } catch (e) {
      debugPrint('[NotificationService] requestPermissions error: $e');
    }
    return false;
  }

  Future<void> showAlertNotification(AlertEvent event) async {
    try {
      final isResistance = event.level.startsWith('R');
      final symName = event.displayName.isNotEmpty
          ? event.displayName
          : (event.symbol.isNotEmpty ? event.symbol : 'ALERT');
      final title = '🚨 $symName TOUCHED ${event.level} @ \$${event.currentPrice.toStringAsFixed(2)}';
      final body = 'Target: \$${event.levelPrice.toStringAsFixed(2)} · ${isResistance ? "Resistance" : "Support"} Level · Tap to view full TradingView chart';

      final androidDetails = AndroidNotificationDetails(
        'gold_alarm_channel_v3',
        '🚨 High Priority Price Level Alarms',
        channelDescription: 'Loud alarm clock notifications for market level touches',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_clock'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        enableLights: true,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        visibility: NotificationVisibility.public,
        ticker: '$symName Level Alert',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: '$symName Alert Terminal',
        ),
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'alarm_clock.wav',
        interruptionLevel: InterruptionLevel.critical,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      final notificationId = (event.level.hashCode ^ event.symbol.hashCode).abs() % 100000;

      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        details,
        payload: event.screenshotPath.isNotEmpty ? event.screenshotPath : event.id,
      );
    } catch (e) {
      debugPrint('[NotificationService] showAlertNotification primary failed ($e), attempting fallback notification...');
      try {
        final fallbackAndroid = AndroidNotificationDetails(
          'gold_alarm_channel_fallback',
          'Price Alerts',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );
        final fallbackDetails = NotificationDetails(android: fallbackAndroid);
        await _notificationsPlugin.show(
          999,
          '🚨 ${event.symbol} TOUCHED ${event.level} @ \$${event.currentPrice.toStringAsFixed(2)}',
          'Target: \$${event.levelPrice.toStringAsFixed(2)} - Price Level Alert Triggered',
          fallbackDetails,
          payload: event.screenshotPath,
        );
      } catch (e2) {
        debugPrint('[NotificationService] Fallback notification failed: $e2');
      }
    }
  }

  /// Direct manual notification test for settings verification
  Future<void> testNotification() async {
    final testEvent = AlertEvent(
      id: 'test_notif_${DateTime.now().millisecondsSinceEpoch}',
      symbol: 'XAUUSD',
      displayName: 'Gold Spot / USD',
      level: 'R2',
      levelPrice: 4580.75,
      currentPrice: 4580.75,
      tolerance: 0.20,
      screenshotPath: '',
      triggerReason: 'Manual Notification Test from Terminal Settings',
      telegramStatus: 'TEST',
      timestamp: DateTime.now(),
      isTest: true,
    );
    await showAlertNotification(testEvent);
  }
}
