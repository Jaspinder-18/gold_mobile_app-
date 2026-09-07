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

    // 1. Create Loud Alarm Notification Channel with raw resource sound & full screen priority
    final alarmChannel = AndroidNotificationChannel(
      'gold_alarm_channel_v4',
      '🚨 High Priority Price Level Alarms',
      description: 'Loud alarm clock sound & high priority notifications for market price touches',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm_clock'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      enableLights: true,
      showBadge: true,
    );

    // 2. Create Standard High-Priority Notification Channel (System Sound)
    final standardChannel = AndroidNotificationChannel(
      'gold_alerts_channel_standard',
      '🔔 Market Price Touch Alerts',
      description: 'Instant notification alerts when market touches custom target price or pivot levels',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 400, 800]),
      enableLights: true,
      showBadge: true,
    );

    // 3. Fallback Notification Channel
    final fallbackChannel = AndroidNotificationChannel(
      'gold_alarm_channel_fallback',
      '⚡ Price Alerts (Fallback)',
      description: 'Fallback notifications for instant price triggers',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(alarmChannel);
      await androidImpl.createNotificationChannel(standardChannel);
      await androidImpl.createNotificationChannel(fallbackChannel);
    }

    _isInitialized = true;
  }

  /// Request runtime permissions on Android 13+ (API 33+) & iOS
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
    final symName = event.displayName.isNotEmpty
        ? event.displayName
        : (event.symbol.isNotEmpty ? event.symbol : 'ALERT');
    final isCustom = event.level.toUpperCase() == 'CUSTOM';
    final isResistance = event.level.startsWith('R');

    final String title;
    final String body;

    if (isCustom) {
      title = '🚨 $symName TOUCHED CUSTOM TARGET @ \$${event.currentPrice.toStringAsFixed(2)}';
      body = 'Custom Target: \$${event.levelPrice.toStringAsFixed(2)} · Price Alert Triggered · Tap to view live chart';
    } else {
      title = '🚨 $symName TOUCHED ${event.level} @ \$${event.currentPrice.toStringAsFixed(2)}';
      body = 'Target: \$${event.levelPrice.toStringAsFixed(2)} · ${isResistance ? "Resistance" : "Support"} Level · Tap to view full chart';
    }

    final notificationId = (event.level.hashCode ^ event.symbol.hashCode ^ (DateTime.now().second)).abs() % 100000;

    try {
      final androidDetails = AndroidNotificationDetails(
        'gold_alarm_channel_v4',
        '🚨 High Priority Price Level Alarms',
        channelDescription: 'Loud alarm clock notifications for market price touches',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
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
        interruptionLevel: InterruptionLevel.critical,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        details,
        payload: event.screenshotPath.isNotEmpty ? event.screenshotPath : event.id,
      );
      debugPrint('[NotificationService] ✓ Primary notification delivered for $symName ${event.level}');
    } catch (e) {
      debugPrint('[NotificationService] showAlertNotification primary channel error: $e, falling back to standard channel...');
      try {
        final standardAndroid = AndroidNotificationDetails(
          'gold_alerts_channel_standard',
          '🔔 Market Price Touch Alerts',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: '$symName Alert Terminal',
          ),
        );
        final fallbackDetails = NotificationDetails(android: standardAndroid);
        await _notificationsPlugin.show(
          notificationId,
          title,
          body,
          fallbackDetails,
          payload: event.screenshotPath.isNotEmpty ? event.screenshotPath : event.id,
        );
        debugPrint('[NotificationService] ✓ Fallback notification delivered for $symName');
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
      level: 'CUSTOM',
      levelPrice: 3450.50,
      currentPrice: 3450.50,
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
