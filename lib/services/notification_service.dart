import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' hide NotificationVisibility;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import '../models/market_data.dart';
import 'audio_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  debugPrint('[FCM Background] Remote message received: ${message.messageId}, data: ${message.data}');

  try {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    final data = message.data;
    final symbol = data['symbol']?.toString() ?? 'XAUUSD';
    final targetPrice = double.tryParse(data['targetPrice']?.toString() ?? '0') ?? 0.0;
    final currentPrice = double.tryParse(data['currentPrice']?.toString() ?? '0') ?? targetPrice;
    final level = data['level']?.toString() ?? 'CUSTOM';
    final screenshotUrl = data['screenshotUrl']?.toString() ?? '';

    final isCustom = level.toUpperCase() == 'CUSTOM';
    final title = message.notification?.title ?? (isCustom
        ? '🚨 $symbol TOUCHED TARGET @ \$${currentPrice.toStringAsFixed(2)}'
        : '🚨 $symbol TOUCHED $level @ \$${currentPrice.toStringAsFixed(2)}');
    final body = message.notification?.body ?? (isCustom
        ? 'Target: \$${targetPrice.toStringAsFixed(2)} · Price Alert Triggered · Tap to view chart'
        : 'Target: \$${targetPrice.toStringAsFixed(2)} · Price Level Alert');

    final notificationId = (level.hashCode ^ symbol.hashCode ^ (DateTime.now().second)).abs() % 100000;

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
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: '$symbol Alert Terminal',
      ),
    );

    final details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      details,
      payload: screenshotUrl.isNotEmpty ? screenshotUrl : (data['alertId'] ?? ''),
    );
  } catch (e) {
    debugPrint('[FCM Background] Error in background handler: $e');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Function(String?)? onNotificationTap;
  bool _isInitialized = false;
  bool _hasPermission = false;
  String? _fcmToken;
  final Map<String, int> _recentHandledAlerts = {};

  bool get hasPermission => _hasPermission;
  String? get fcmToken => _fcmToken;

  void recordRecentAlert(String alertId) {
    if (alertId.isNotEmpty) {
      _recentHandledAlerts[alertId] = DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<void> initialize({String? serverUrl}) async {
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

    // 1. Loud Alarm Notification Channel with raw resource sound & full screen priority
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

    // 2. Standard High-Priority Channel
    final standardChannel = AndroidNotificationChannel(
      'gold_alerts_channel_standard',
      '🔔 Market Price Touch Alerts',
      description: 'Instant notification alerts when market touches custom target price',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 400, 800]),
      enableLights: true,
      showBadge: true,
    );

    final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(alarmChannel);
      await androidImpl.createNotificationChannel(standardChannel);
    }

    // 3. Initialize Firebase Messaging
    await _initFirebaseMessaging(serverUrl: serverUrl);

    _isInitialized = true;
  }

  Future<void> _initFirebaseMessaging({String? serverUrl}) async {
    try {
      try {
        await Firebase.initializeApp();
      } catch (e) {
        debugPrint('[NotificationService] Firebase.initializeApp note: $e');
      }

      final messaging = FirebaseMessaging.instance;

      // Request FCM permission
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      _hasPermission = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      // Subscribe to topics
      try {
        await messaging.subscribeToTopic('all_alerts');
        debugPrint('[NotificationService] Subscribed to FCM topic: all_alerts');
      } catch (e) {
        debugPrint('[NotificationService] Topic subscription note: $e');
      }

      // Get FCM Token
      try {
        _fcmToken = await messaging.getToken();
        debugPrint('[NotificationService] FCM Token retrieved: $_fcmToken');
        if (_fcmToken != null && serverUrl != null) {
          await registerTokenWithServer(serverUrl, _fcmToken!);
        }
      } catch (e) {
        debugPrint('[NotificationService] getToken note: $e');
      }

      // Listen to token refreshes
      messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (serverUrl != null) {
          registerTokenWithServer(serverUrl, newToken);
        }
      });

      // Foreground message handler (deduplicated against Socket.IO)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[NotificationService] Foreground FCM message received: ${message.data}');
        final data = message.data;
        final alertId = data['alertId']?.toString() ?? message.messageId ?? '';
        final now = DateTime.now().millisecondsSinceEpoch;

        if (alertId.isNotEmpty && _recentHandledAlerts.containsKey(alertId)) {
          final lastHandled = _recentHandledAlerts[alertId] ?? 0;
          if ((now - lastHandled) < 20000) {
            debugPrint('[NotificationService] Ignoring duplicate foreground FCM for already-handled alert: $alertId');
            return;
          }
        }
        if (alertId.isNotEmpty) {
          _recentHandledAlerts[alertId] = now;
        }

        final symbol = data['symbol']?.toString() ?? 'XAUUSD';
        final targetPrice = double.tryParse(data['targetPrice']?.toString() ?? '0') ?? 0.0;
        final currentPrice = double.tryParse(data['currentPrice']?.toString() ?? '0') ?? targetPrice;
        final level = data['level']?.toString() ?? 'CUSTOM';
        final screenshotUrl = data['screenshotUrl']?.toString() ?? '';

        final event = AlertEvent(
          id: alertId.isNotEmpty ? alertId : 'fcm_${DateTime.now().millisecondsSinceEpoch}',
          symbol: symbol,
          displayName: '$symbol Spot',
          level: level,
          levelPrice: targetPrice,
          currentPrice: currentPrice,
          tolerance: 0.20,
          screenshotPath: screenshotUrl,
          triggerReason: message.notification?.body ?? '$symbol touched target price @ \$$currentPrice',
          telegramStatus: 'SENT',
          timestamp: DateTime.now(),
          isTest: false,
        );

        showAlertNotification(event);
        try { AudioService().playAlertSound(); } catch (_) {}
      });

      // When notification opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[NotificationService] FCM Notification clicked to open app: ${message.data}');
        final payload = message.data['screenshotUrl'] ?? message.data['alertId'];
        if (payload != null && onNotificationTap != null) {
          onNotificationTap?.call(payload.toString());
        }
      });

      // When app opened from TERMINATED / FULLY CLOSED state via notification tap
      try {
        final initialMsg = await messaging.getInitialMessage();
        if (initialMsg != null) {
          debugPrint('[NotificationService] App launched from terminated state via FCM: ${initialMsg.data}');
          final payload = initialMsg.data['screenshotUrl'] ?? initialMsg.data['alertId'];
          if (payload != null) {
            Future.delayed(const Duration(milliseconds: 600), () {
              onNotificationTap?.call(payload.toString());
            });
          }
        }
      } catch (e) {
        debugPrint('[NotificationService] getInitialMessage error: $e');
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[NotificationService] Firebase Messaging init exception: $e');
    }
  }

  /// Register FCM Token with backend server
  Future<void> registerTokenWithServer(String serverUrl, String token) async {
    try {
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      await http.post(
        Uri.parse('$cleanUrl/api/alerts/fcm/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
          'deviceName': 'Mobile Client',
          'symbolSubscriptions': ['ALL']
        }),
      ).timeout(const Duration(seconds: 5));
      debugPrint('[NotificationService] ✓ Registered FCM token with server.');
    } catch (e) {
      debugPrint('[NotificationService] registerTokenWithServer error: $e');
    }
  }

  /// Request runtime permissions on Android 13+ (API 33+) & iOS, and request battery optimization bypass
  Future<bool> requestPermissions() async {
    try {
      final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final granted = await androidImpl.requestNotificationsPermission();
        _hasPermission = granted ?? false;

        // Automatically request ignoring battery optimization to bypass Android Doze mode
        try {
          final isIgnoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
          if (!isIgnoring) {
            await FlutterForegroundTask.requestIgnoreBatteryOptimization();
          }
        } catch (_) {}

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

  /// Check if the app is already exempt from battery optimization
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  /// Request prompt to disable battery optimization for 24/7 background alerts
  Future<bool> requestIgnoreBatteryOptimization() async {
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      return false;
    }
  }

  /// Open system battery optimization settings page
  Future<bool> openIgnoreBatteryOptimizationSettings() async {
    try {
      return await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (_) {
      return false;
    }
  }

  /// Check if overlay permission (draw over other apps / pop-up on lock screen) is granted
  Future<bool> canDrawOverlays() async {
    try {
      return await FlutterForegroundTask.canDrawOverlays;
    } catch (_) {
      return false;
    }
  }

  /// Open system overlay / pop-up window settings
  Future<bool> openSystemAlertWindowSettings() async {
    try {
      return await FlutterForegroundTask.openSystemAlertWindowSettings();
    } catch (_) {
      return false;
    }
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
      title = '🚨 $symName TOUCHED TARGET @ \$${event.currentPrice.toStringAsFixed(2)}';
      body = 'Target: \$${event.levelPrice.toStringAsFixed(2)} · Price Alert Triggered · Tap to view live chart';
    } else {
      title = '🚨 $symName TOUCHED ${event.level} @ \$${event.currentPrice.toStringAsFixed(2)}';
      body = 'Target: \$${event.levelPrice.toStringAsFixed(2)} · ${isResistance ? "Resistance" : "Support"} Level';
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
      debugPrint('[NotificationService] ✓ Primary notification delivered for $symName');
    } catch (e) {
      debugPrint('[NotificationService] Primary notification error: $e, using standard channel...');
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
      } catch (_) {}
    }
  }

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
