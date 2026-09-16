import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' hide NotificationVisibility;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:android_intent_plus/android_intent.dart' as android_intent;
import 'package:android_intent_plus/flag.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/market_data.dart';
import '../firebase_options.dart';
import 'audio_service.dart';

Future<void> _acquireWakeLock() async {
  // Keep empty to avoid popping over lock screen or hijacking keyguard
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  debugPrint('[FCM Background] Remote message received: ${message.messageId}, data: ${message.data}');

  try {
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = prefs.getBool('alert_sound_enabled') ?? true;
    final vibrationEnabled = prefs.getBool('alert_vibration_enabled') ?? true;

    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    try {
      await flutterLocalNotificationsPlugin.initialize(initSettings);
    } catch (_) {}

    final androidImpl = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final alarmChannel = AndroidNotificationChannel(
        'gold_price_alerts_v5',
        '🚨 High Priority Price Level Alarms',
        description: 'Loud alarm clock notifications for market price touches',
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_clock'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        enableLights: true,
        showBadge: true,
      );
      final vibrateOnlyChannel = AndroidNotificationChannel(
        'gold_price_alerts_vibrate_only',
        '📳 Price Level Alarms (Vibrate Only)',
        description: 'Vibration only alerts without sound for market price touches',
        importance: Importance.max,
        playSound: false,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        enableLights: true,
        showBadge: true,
      );
      try {
        await androidImpl.createNotificationChannel(alarmChannel);
        await androidImpl.createNotificationChannel(vibrateOnlyChannel);
      } catch (_) {}
      try {
        await androidImpl.requestNotificationsPermission();
      } catch (_) {}
    }

    final data = message.data;
    final symbol = data['symbol']?.toString() ?? 'XAUUSD';
    final targetPrice = double.tryParse(data['targetPrice']?.toString() ?? '0') ?? 0.0;
    final currentPrice = double.tryParse(
        data['currentPrice']?.toString() ?? data['touchedPrice']?.toString() ?? '0') ?? targetPrice;
    final level = data['level']?.toString() ?? 'CUSTOM';
    final screenshotUrl = data['screenshotUrl']?.toString() ?? '';

    final isCustom = level.toUpperCase() == 'CUSTOM';
    final title = message.notification?.title ?? (isCustom
        ? '🚨 $symbol TOUCHED TARGET @ \$${currentPrice.toStringAsFixed(2)}'
        : '🚨 $symbol TOUCHED $level @ \$${currentPrice.toStringAsFixed(2)}');
    final body = message.notification?.body ?? (isCustom
        ? 'Target: \$${targetPrice.toStringAsFixed(2)} · Price Alert Triggered · Tap to view chart'
        : 'Target: \$${targetPrice.toStringAsFixed(2)} · Price Level Alert');

    final notificationId =
        (level.hashCode ^ symbol.hashCode ^ DateTime.now().millisecondsSinceEpoch).abs() % 2147483647;

    final isVibrateOnly = !soundEnabled && vibrationEnabled;
    final activeChannelId = isVibrateOnly ? 'gold_price_alerts_vibrate_only' : 'gold_price_alerts_v5';

    final androidDetails = AndroidNotificationDetails(
      activeChannelId,
      isVibrateOnly ? '📳 Price Level Alarms (Vibrate Only)' : '🚨 High Priority Price Level Alarms',
      channelDescription: isVibrateOnly
          ? 'Vibration only alerts without sound for market price touches'
          : 'Loud alarm clock notifications for market price touches',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      timeoutAfter: 600000,
      playSound: soundEnabled,
      sound: soundEnabled ? const RawResourceAndroidNotificationSound('alarm_clock') : null,
      enableVibration: vibrationEnabled,
      vibrationPattern: vibrationEnabled ? Int64List.fromList([0, 1000, 500, 1000, 500, 1000]) : null,
      enableLights: true,
      ledColor: const Color(0xFFF59E0B),
      ledOnMs: 500,
      ledOffMs: 500,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      ticker: '$symbol Level Alert',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: '$symbol Alert Terminal',
      ),
      actions: [
        const AndroidNotificationAction('view_chart', 'View Chart', showsUserInterface: true),
        const AndroidNotificationAction('dismiss_alert', 'Cancel', showsUserInterface: false, cancelNotification: true),
      ],
    );

    final payloadMap = {
      'symbol': symbol,
      'currentPrice': currentPrice,
      'targetPrice': targetPrice,
      'level': level,
      'timestamp': DateTime.now().toIso8601String(),
      'screenshotUrl': screenshotUrl,
      'alertId': data['alertId'] ?? '',
    };

    final details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      details,
      payload: json.encode(payloadMap),
    );

    if (soundEnabled) {
      try {
        await AudioService.playAlertSoundDirect();
      } catch (_) {}
    } else if (vibrationEnabled) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  } catch (e) {
    debugPrint('[FCM Background] Error in background handler: $e');
    try {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      try {
        await flutterLocalNotificationsPlugin.initialize(initSettings);
      } catch (_) {}
      final fallbackAndroid = AndroidNotificationDetails(
        'gold_price_alerts_v5',
        '🚨 High Priority Price Level Alarms',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: false,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        visibility: NotificationVisibility.public,
        actions: [
          const AndroidNotificationAction('view_chart', 'View Chart', showsUserInterface: true),
          const AndroidNotificationAction('dismiss_alert', 'Cancel', showsUserInterface: false, cancelNotification: true),
        ],
      );
      final sym = message.data['symbol']?.toString() ?? 'XAUUSD';
      final pr = message.data['currentPrice']?.toString() ??
          message.data['touchedPrice']?.toString() ??
          message.data['targetPrice']?.toString() ?? 'ALERT';
      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        '🚨 $sym ALERT @ \$$pr',
        'Price level alert triggered. Tap to open.',
        NotificationDetails(android: fallbackAndroid),
      );
    } catch (_) {}
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  static NotificationService get instance => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Function(String?)? _onNotificationTap;
  String? _pendingPayload;
  bool _isInitialized = false;
  bool _hasPermission = false;
  String? _fcmToken;
  final Map<String, int> _recentHandledAlerts = {};

  static const String channelId = 'gold_price_alerts_v5';
  static const String channelName = '🚨 High Priority Price Level Alarms';
  static const String channelDescription =
      'Loud alarm clock notifications for market price touches';

  bool get hasPermission => _hasPermission;
  String? get fcmToken => _fcmToken;
  String? get pendingPayload => _pendingPayload;
  bool get isInitialized => _isInitialized;

  Function(String?)? get onNotificationTap => _onNotificationTap;
  set onNotificationTap(Function(String?)? handler) {
    _onNotificationTap = handler;
    if (handler != null && _pendingPayload != null) {
      final payload = _pendingPayload;
      _pendingPayload = null;
      Future.delayed(const Duration(milliseconds: 300), () {
        handler(payload);
      });
    }
  }

  void recordRecentAlert(String alertId) {
    if (alertId.isNotEmpty) {
      _recentHandledAlerts[alertId] = DateTime.now().millisecondsSinceEpoch;
    }
  }

  void _handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (_onNotificationTap != null) {
      _onNotificationTap?.call(payload);
    } else {
      _pendingPayload = payload;
    }
  }

  Future<String> _resolveServerUrl(String? serverUrl) async {
    if (serverUrl != null && serverUrl.trim().isNotEmpty) {
      return serverUrl.trim();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('server_url');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        return savedUrl.trim();
      }
    } catch (_) {}
    return 'https://gold-server-dbbq.onrender.com';
  }

  Future<void> initialize({String? serverUrl}) async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.actionId == 'dismiss_alert' || response.actionId == 'cancel') {
          AudioService().stop();
          return;
        }
        AudioService().stop();
        _handlePayload(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: _bgNotificationTap,
    );

    final alarmChannel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm_clock'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      enableLights: true,
      ledColor: const Color(0xFFF59E0B),
      showBadge: true,
    );

    final vibrateOnlyChannel = AndroidNotificationChannel(
      'gold_price_alerts_vibrate_only',
      '📳 Price Level Alarms (Vibrate Only)',
      description: 'Vibration only alerts without sound for market price touches',
      importance: Importance.max,
      playSound: false,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      enableLights: true,
      ledColor: const Color(0xFFF59E0B),
      showBadge: true,
    );

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
      try {
        await androidImpl.createNotificationChannel(alarmChannel);
      } catch (_) {}
      try {
        await androidImpl.createNotificationChannel(vibrateOnlyChannel);
      } catch (_) {}
      try {
        await androidImpl.createNotificationChannel(standardChannel);
      } catch (_) {}
      try {
        final granted = await androidImpl.requestNotificationsPermission();
        _hasPermission = granted ?? false;
      } catch (_) {}
      try {
        await androidImpl.requestExactAlarmsPermission();
      } catch (_) {}
    }

    final iosImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      try {
        await iosImpl.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          critical: true,
        );
      } catch (_) {}
    }

    await _initFirebaseMessaging(serverUrl: serverUrl);
    _isInitialized = true;
  }

  Future<void> _initFirebaseMessaging({String? serverUrl}) async {
    try {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        debugPrint('[NotificationService] Firebase.initializeApp note: $e');
      }

      final messaging = FirebaseMessaging.instance;

      try {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}

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
      debugPrint('[FCM] Notification authorization status: ${settings.authorizationStatus}');

      try {
        await messaging.subscribeToTopic('all_alerts');
        debugPrint('[NotificationService] Subscribed to FCM topic: all_alerts');
      } catch (e) {
        debugPrint('[NotificationService] Topic subscription note: $e');
      }

      final resolvedUrl = await _resolveServerUrl(serverUrl);
      try {
        _fcmToken = await messaging.getToken();
        debugPrint('[FCM] Token received: $_fcmToken');
        if (_fcmToken != null && _fcmToken!.isNotEmpty) {
          await registerTokenWithServer(resolvedUrl, _fcmToken!);
        }
      } catch (e) {
        debugPrint('[FCM] getToken note: $e');
      }

      messaging.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        debugPrint('[FCM] Token refreshed: $newToken');
        final currentUrl = await _resolveServerUrl(null);
        await registerTokenWithServer(currentUrl, newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM] Foreground message received: ${message.data}');
        final data = message.data;
        final alertId = data['alertId']?.toString() ?? message.messageId ?? '';
        final now = DateTime.now().millisecondsSinceEpoch;

        if (alertId.isNotEmpty && _recentHandledAlerts.containsKey(alertId)) {
          final lastHandled = _recentHandledAlerts[alertId] ?? 0;
          if ((now - lastHandled) < 20000) {
            debugPrint('[NotificationService] Ignoring duplicate foreground FCM for alert: $alertId');
            return;
          }
        }
        if (alertId.isNotEmpty) {
          _recentHandledAlerts[alertId] = now;
        }

        final symbol = data['symbol']?.toString() ?? 'XAUUSD';
        final targetPrice = double.tryParse(data['targetPrice']?.toString() ?? '0') ?? 0.0;
        final currentPrice = double.tryParse(
            data['currentPrice']?.toString() ?? data['touchedPrice']?.toString() ?? '0') ?? targetPrice;
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
        try {
          AudioService.instance.playAlertSound();
        } catch (_) {}
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[FCM] Notification opened from background: ${message.data}');
        final payload = message.data['screenshotUrl'] ?? message.data['alertId'];
        _handlePayload(payload?.toString());
      });

      try {
        final initialMsg = await messaging.getInitialMessage();
        if (initialMsg != null) {
          debugPrint('[FCM] Notification opened from terminated state: ${initialMsg.data}');
          final payload = initialMsg.data['screenshotUrl'] ?? initialMsg.data['alertId'];
          _handlePayload(payload?.toString());
        }
      } catch (e) {
        debugPrint('[FCM] getInitialMessage error: $e');
      }
    } catch (e) {
      debugPrint('[NotificationService] Firebase Messaging init exception: $e');
    }
  }

  Future<void> registerTokenWithServer(String serverUrl, String token) async {
    if (token.isEmpty) return;
    try {
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final response = await http
          .post(
            Uri.parse('$cleanUrl/api/alerts/fcm/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'token': token,
              'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
              'deviceName': 'Mobile Client',
              'symbolSubscriptions': ['ALL']
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[FCM] Token registered with backend: $cleanUrl');
      } else {
        debugPrint('[FCM] Token registration response status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[FCM] Token registration error: $e');
    }
  }

  Future<bool> sendFcmTestPush({String? serverUrl}) async {
    try {
      final resolvedUrl = await _resolveServerUrl(serverUrl);
      final cleanUrl = resolvedUrl.replaceAll(RegExp(r'/+$'), '');

      if (_fcmToken == null || _fcmToken!.isEmpty) {
        try {
          _fcmToken = await FirebaseMessaging.instance.getToken();
        } catch (_) {}
      }

      final response = await http
          .post(
            Uri.parse('$cleanUrl/api/alerts/fcm/test'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'token': _fcmToken}),
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[NotificationService] sendFcmTestPush error: $e');
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final granted = await androidImpl.requestNotificationsPermission();
        _hasPermission = granted ?? false;
        try {
          await androidImpl.requestExactAlarmsPermission();
        } catch (_) {}
        try {
          await androidImpl.requestFullScreenIntentPermission();
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
          critical: true,
        );
        _hasPermission = granted ?? false;
        return _hasPermission;
      }
    } catch (e) {
      debugPrint('[NotificationService] requestPermissions error: $e');
    }
    return false;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestIgnoreBatteryOptimization() async {
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      return false;
    }
  }

  Future<bool> openIgnoreBatteryOptimizationSettings() async {
    try {
      return await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (_) {
      return false;
    }
  }

  Future<bool> canDrawOverlays() async {
    try {
      return await FlutterForegroundTask.canDrawOverlays;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openSystemAlertWindowSettings() async {
    try {
      return await FlutterForegroundTask.openSystemAlertWindowSettings();
    } catch (_) {
      return false;
    }
  }

  Future<void> requestAllSpecialPermissions({bool force = false}) async {
    try {
      if (!_hasPermission || force) {
        await requestPermissions();
      }
    } catch (_) {}

    try {
      final ignoring = await isIgnoringBatteryOptimizations();
      if (!ignoring) {
        try {
          await requestIgnoreBatteryOptimization();
        } catch (_) {
          await openIgnoreBatteryOptimizationSettings();
        }
      }
    } catch (_) {}

    try {
      final overlay = await canDrawOverlays();
      if (!overlay) {
        try {
          await openSystemAlertWindowSettings();
        } catch (_) {}
      }
    } catch (_) {}

    try {
      await openAutoStartSettingsIfNeeded();
    } catch (_) {}
  }

  Future<void> openAutoStartSettingsIfNeeded() async {
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return;
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final info = await deviceInfo.androidInfo;
      final brand = info.brand.toLowerCase();
      final manufacturer = info.manufacturer.toLowerCase();
      final model = info.model.toLowerCase();

      String? action;
      String? package;
      String? className;

      if (brand.contains('xiaomi') || manufacturer.contains('xiaomi') || model.contains('redmi') || model.contains('mi ')) {
        action = 'miui.intent.action.OP_AUTO_START';
        package = 'com.miui.securitycenter';
        className = 'com.miui.permcenter.autostart.AutoStartManagementActivity';
      } else if (brand.contains('huawei') || manufacturer.contains('huawei') || brand.contains('honor')) {
        action = 'com.huawei.systemmanager.optimize.process.ProtectActivity';
        package = 'com.huawei.systemmanager';
      } else if (brand.contains('oppo') || manufacturer.contains('oppo') || brand.contains('realme') || manufacturer.contains('realme')) {
        package = 'com.coloros.safecenter';
        className = 'com.coloros.safecenter.permission.startup.StartupAppListActivity';
      } else if (brand.contains('vivo') || manufacturer.contains('vivo') || brand.contains('iqoo')) {
        package = 'com.vivo.permissionmanager';
        className = 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity';
      } else if (brand.contains('samsung') || manufacturer.contains('samsung')) {
        package = 'com.samsung.android.lool';
        className = 'com.samsung.android.sm.ui.battery.BatteryActivity';
      } else if (brand.contains('oneplus') || manufacturer.contains('oneplus')) {
        package = 'com.oneplus.security';
        className = 'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity';
      } else if (brand.contains('asus') || manufacturer.contains('asus')) {
        package = 'com.asus.mobilemanager';
        className = 'com.asus.mobilemanager.autostart.AutoStartActivity';
      } else if (brand.contains('lenovo') || manufacturer.contains('lenovo')) {
        package = 'com.lenovo.security';
        className = 'com.lenovo.security.backgroundmgmt.BackgroundAppManagementActivity';
      }

      if (action != null || package != null) {
        try {
          final intent = android_intent.AndroidIntent(
            action: action,
            package: package,
            componentName: className != null && package != null ? '$package/$className' : null,
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
          );
          await intent.launch();
        } catch (_) {
          try {
            final pkg = (await PackageInfo.fromPlatform()).packageName;
            final intent = android_intent.AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$pkg',
              flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
            );
            await intent.launch();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Auto-start opener error: $e');
    }
  }

  Future<Uint8List?> _downloadImageBytes(String? pathOrUrl) async {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
    try {
      String fullUrl = pathOrUrl;
      if (!fullUrl.startsWith('http://') && !fullUrl.startsWith('https://')) {
        final serverUrl = await _resolveServerUrl(null);
        fullUrl = '${serverUrl.replaceAll(RegExp(r'/+$'), '')}${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
      }
      final response = await http.get(Uri.parse(fullUrl)).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<void> showAlertNotification(AlertEvent event) async {
    try {
      await _acquireWakeLock();
    } catch (_) {}

    // 1. Strict Anti-Duplicate Debounce Window (25 seconds per symbol-price touch)
    final debounceKey = '${event.symbol}_${event.levelPrice.toStringAsFixed(2)}';
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_recentHandledAlerts.containsKey(debounceKey)) {
      final lastTime = _recentHandledAlerts[debounceKey] ?? 0;
      if ((now - lastTime) < 25000) {
        debugPrint('[NotificationService] Deduplicating notification for: $debounceKey');
        return;
      }
    }
    _recentHandledAlerts[debounceKey] = now;

    // Prune old debounce entries older than 60s
    _recentHandledAlerts.removeWhere((_, time) => (now - time) > 60000);

    final symName =
        event.displayName.isNotEmpty ? event.displayName : (event.symbol.isNotEmpty ? event.symbol : 'ALERT');
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

    final notificationId =
        (event.level.hashCode ^ event.symbol.hashCode ^ DateTime.now().millisecondsSinceEpoch).abs() %
            2147483647;

    final isSoundEnabled = AudioService.instance.soundEnabled;
    final isVibrationEnabled = AudioService.instance.vibrationEnabled;
    final isVibrateOnly = !isSoundEnabled && isVibrationEnabled;
    final activeChannelId = isVibrateOnly ? 'gold_price_alerts_vibrate_only' : channelId;

    // Download screenshot image for rich BigPicture notification
    final imageBytes = await _downloadImageBytes(event.screenshotPath);

    final StyleInformation styleInformation = imageBytes != null
        ? BigPictureStyleInformation(
            ByteArrayAndroidBitmap(imageBytes),
            contentTitle: title,
            summaryText: body,
            hideExpandedLargeIcon: true,
          )
        : BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: '$symName Alert Terminal',
          );

    try {
      final androidDetails = AndroidNotificationDetails(
        activeChannelId,
        isVibrateOnly ? '📳 Price Level Alarms (Vibrate Only)' : channelName,
        channelDescription: isVibrateOnly
            ? 'Vibration only alerts without sound for market price touches'
            : channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: false,
        ongoing: false,
        autoCancel: true,
        showWhen: true,
        when: DateTime.now().millisecondsSinceEpoch,
        timeoutAfter: 600000,
        playSound: isSoundEnabled,
        sound: isSoundEnabled ? const RawResourceAndroidNotificationSound('alarm_clock') : null,
        enableVibration: isVibrationEnabled,
        vibrationPattern: isVibrationEnabled ? Int64List.fromList([0, 1000, 500, 1000, 500, 1000]) : null,
        enableLights: true,
        ledColor: const Color(0xFFF59E0B),
        ledOnMs: 500,
        ledOffMs: 500,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        visibility: NotificationVisibility.public,
        ticker: '$symName Level Alert',
        styleInformation: styleInformation,
        actions: [
          const AndroidNotificationAction('dismiss_alert', 'Cancel Alarm', showsUserInterface: false, cancelNotification: true),
          const AndroidNotificationAction('view_chart', 'View Chart', showsUserInterface: true),
        ],
      );

      final darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: isSoundEnabled,
        interruptionLevel: InterruptionLevel.critical,
      );

      final payloadMap = {
        'symbol': event.symbol,
        'currentPrice': event.currentPrice,
        'targetPrice': event.levelPrice,
        'level': event.level,
        'timestamp': event.timestamp.toIso8601String(),
        'screenshotUrl': event.screenshotPath,
        'alertId': event.id,
      };

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        details,
        payload: json.encode(payloadMap),
      );
      debugPrint('[NotificationService] ✓ Primary notification delivered for $symName with chart=${imageBytes != null}');
    } catch (e) {
      debugPrint('[NotificationService] Primary notification error: $e, using standard channel...');
      try {
        final standardAndroid = AndroidNotificationDetails(
          'gold_alerts_channel_standard',
          '🔔 Market Price Touch Alerts',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: false,
          playSound: isSoundEnabled,
          enableVibration: isVibrationEnabled,
          visibility: NotificationVisibility.public,
          timeoutAfter: 600000,
          styleInformation: styleInformation,
          actions: [
            const AndroidNotificationAction('dismiss_alert', 'Cancel Alarm', showsUserInterface: false, cancelNotification: true),
            const AndroidNotificationAction('view_chart', 'View Chart', showsUserInterface: true),
          ],
        );
        final payloadMap = {
          'symbol': event.symbol,
          'currentPrice': event.currentPrice,
          'targetPrice': event.levelPrice,
          'level': event.level,
          'timestamp': event.timestamp.toIso8601String(),
          'screenshotUrl': event.screenshotPath,
          'alertId': event.id,
        };
        final fallbackDetails = NotificationDetails(android: standardAndroid);
        await _notificationsPlugin.show(
          notificationId,
          title,
          body,
          fallbackDetails,
          payload: json.encode(payloadMap),
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

@pragma('vm:entry-point')
void _bgNotificationTap(NotificationResponse response) {
  debugPrint('[NotificationService] BG notification tap action: ${response.actionId}');
  AudioService.instance.stopAlarm();
}
