import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' hide NotificationVisibility;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MarketAlertTaskHandler());
}

class MarketAlertTaskHandler extends TaskHandler {
  String _serverUrl = 'https://gold-server-dbbq.onrender.com';
  String _activeSymbol = 'XAUUSD';
  double _previousPrice = 0.0;
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Map<String, int> _lastAlertFired = {};

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BackgroundService] onStart starter=$starter at ${timestamp.toIso8601String()}');
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString('server_url') ?? 'https://gold-server-dbbq.onrender.com';
      _activeSymbol = prefs.getString('active_symbol') ?? 'XAUUSD';

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      try {
        await _notificationsPlugin.initialize(initSettings);
      } catch (_) {}

      final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        try {
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
          await androidImpl.createNotificationChannel(alarmChannel);
        } catch (_) {}
      }

      try {
        FlutterForegroundTask.updateService(
          notificationTitle: '📊 $_activeSymbol · Market Monitor',
          notificationText: 'Live price guard active · 24/7 alerts',
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('[BackgroundService] onStart error: $e');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastPoll.millisecondsSinceEpoch < 4000) return;
      _lastPoll = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString('server_url') ?? _serverUrl;
      _activeSymbol = prefs.getString('active_symbol') ?? _activeSymbol;

      final symKey = _activeSymbol.toUpperCase();
      final targetPrice = prefs.getDouble('custom_target_price_$symKey') ?? 0.0;
      final enabled = prefs.getBool('custom_price_alert_enabled_$symKey') ?? false;

      final cleanUrl = _serverUrl.replaceAll(RegExp(r'/+$'), '');
      http.Response? res;
      try {
        res = await http
            .get(Uri.parse('$cleanUrl/api/market/latest?symbol=$_activeSymbol'))
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        try {
          res = await http
              .get(Uri.parse('https://gold-server-dbbq.onrender.com/api/market/latest?symbol=$_activeSymbol'))
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      if (res != null && res.statusCode == 200) {
        final data = json.decode(res.body);
        final priceData = data['data'] ?? data;
        final currentPrice = double.tryParse(priceData['price']?.toString() ?? '0') ?? 0.0;

        if (currentPrice > 0) {
          try {
            FlutterForegroundTask.updateService(
              notificationTitle: '📊 $_activeSymbol · \$${currentPrice.toStringAsFixed(2)}',
              notificationText: enabled && targetPrice > 0
                  ? 'Target: \$${targetPrice.toStringAsFixed(2)} · Live Alarm Guard Active'
                  : 'Market Alert Monitor Active · 24/7 Protection',
            );
          } catch (_) {}

          if (enabled && targetPrice > 0) {
            const tolerance = 0.25;
            final diff = (currentPrice - targetPrice).abs();
            final isTouching = diff <= tolerance;
            final crossedUp =
                _previousPrice > 0 && _previousPrice < targetPrice && currentPrice >= targetPrice;
            final crossedDown =
                _previousPrice > 0 && _previousPrice > targetPrice && currentPrice <= targetPrice;
            final alertKey = '${symKey}_${targetPrice.toStringAsFixed(2)}';
            final lastFired = _lastAlertFired[alertKey] ?? 0;
            final debounceMs = DateTime.now().millisecondsSinceEpoch - lastFired;

            if ((isTouching || crossedUp || crossedDown) && debounceMs > 120000) {
              debugPrint(
                  '[BackgroundService] 🚨 TARGET PRICE TOUCHED IN BACKGROUND: $_activeSymbol @ \$$currentPrice (Target: \$$targetPrice)');

              _lastAlertFired[alertKey] = DateTime.now().millisecondsSinceEpoch;
              await prefs.setBool('custom_price_alert_enabled_$symKey', false);

              final notificationId = (_activeSymbol.hashCode ^
                      targetPrice.hashCode ^
                      DateTime.now().second)
                  .abs() %
                  2147483647;

              final androidDetails = AndroidNotificationDetails(
                'gold_price_alerts_v5',
                '🚨 High Priority Price Level Alarms',
                channelDescription: 'Loud alarm clock notifications for market price touches',
                importance: Importance.max,
                priority: Priority.max,
                fullScreenIntent: false,
                ongoing: false,
                autoCancel: true,
                showWhen: true,
                when: DateTime.now().millisecondsSinceEpoch,
                timeoutAfter: 600000,
                playSound: true,
                sound: const RawResourceAndroidNotificationSound('alarm_clock'),
                enableVibration: true,
                vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
                enableLights: true,
                ledColor: const Color(0xFFF59E0B),
                category: AndroidNotificationCategory.alarm,
                audioAttributesUsage: AudioAttributesUsage.alarm,
                visibility: NotificationVisibility.public,
                styleInformation: BigTextStyleInformation(
                  'Target: \$${targetPrice.toStringAsFixed(2)} · Custom Price Alert Triggered · Tap to view live chart',
                  contentTitle:
                      '🚨 $_activeSymbol TOUCHED TARGET @ \$${currentPrice.toStringAsFixed(2)}',
                  summaryText: '$_activeSymbol Alert Terminal',
                ),
              );

              try {
                await _notificationsPlugin.show(
                  notificationId,
                  '🚨 $_activeSymbol TOUCHED TARGET @ \$${currentPrice.toStringAsFixed(2)}',
                  'Target: \$${targetPrice.toStringAsFixed(2)} · Custom Price Alert Triggered',
                  NotificationDetails(android: androidDetails),
                  payload: 'alert_$notificationId',
                );
              } catch (_) {}
            }
          }
          _previousPrice = currentPrice;
        }
      }
    } catch (e) {
      debugPrint('[BackgroundService] onRepeatEvent error (silent): $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isDestroyed) async {
    debugPrint('[BackgroundService] onDestroy: isDestroyed=$isDestroyed');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('foreground_service_expected_stop', true);
    } catch (_) {}
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['activeSymbol'] != null) _activeSymbol = map['activeSymbol'].toString();
      if (map['serverUrl'] != null) _serverUrl = map['serverUrl'].toString();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[BackgroundService] Notification button: $id');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  static BackgroundService get instance => _instance;
  BackgroundService._internal();

  bool _isServiceRunning = false;
  bool get isRunning => _isServiceRunning;

  Future<void> initialize() async {
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        _isServiceRunning = true;
        return;
      }
      _configureForegroundTaskDefaults();
    } catch (e) {
      debugPrint('[BackgroundService] initialize error: $e');
    }
  }

  void _configureForegroundTaskDefaults() {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'gold_price_alerts_v5',
          channelName: '🚨 High Priority Price Level Alarms',
          channelDescription: 'Persistent market monitor foreground service',
          channelImportance: NotificationChannelImportance.MAX,
          priority: NotificationPriority.HIGH,
          showWhen: true,
          showBadge: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(3000),
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    } catch (_) {}
  }

  Future<bool> startService({
    String symbol = 'XAUUSD',
    double targetPrice = 0.0,
    bool enabled = false,
    String serverUrl = '',
  }) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        try {
          await FlutterForegroundTask.stopService();
        } catch (_) {}
      }
      _configureForegroundTaskDefaults();

      final prefs = await SharedPreferences.getInstance();
      final effectiveUrl = serverUrl.isNotEmpty
          ? serverUrl
          : (prefs.getString('server_url') ?? 'https://gold-server-dbbq.onrender.com');
      final effectiveSymbol = symbol.isNotEmpty ? symbol : (prefs.getString('active_symbol') ?? 'XAUUSD');

      await _ensurePermissions();
      _configureForegroundTaskDefaults();

      final result = await FlutterForegroundTask.startService(
        notificationTitle: '📊 $effectiveSymbol · Market Monitor Starting',
        notificationText: 'Initializing live price guard...',
        callback: startCallback,
      );

      final isSuccess = result.toString().toLowerCase().contains('success') || (await FlutterForegroundTask.isRunningService);

      if (isSuccess) {
        try {
          FlutterForegroundTask.sendDataToTask({
            'activeSymbol': effectiveSymbol,
            'serverUrl': effectiveUrl,
          });
        } catch (_) {}
        _isServiceRunning = true;
        debugPrint('[BackgroundService] ✓ Foreground service STARTED for $effectiveSymbol');
        return true;
      } else {
        debugPrint('[BackgroundService] startService failed with: $result');
        return false;
      }
    } catch (e) {
      debugPrint('[BackgroundService] startService error: $e');
      return false;
    }
  }

  Future<bool> _ensurePermissions() async {
    try {
      final canDrawResult = await FlutterForegroundTask.canDrawOverlays;
      if (!canDrawResult) {
        try {
          await FlutterForegroundTask.openSystemAlertWindowSettings();
        } catch (_) {}
      }
    } catch (_) {}
    try {
      final ignoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!ignoring) {
        try {
          final result = await FlutterForegroundTask.requestIgnoreBatteryOptimization();
          if (!result) {
            try {
              await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
            } catch (_) {}
          }
        } catch (_) {
          try {
            await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return true;
  }

  Future<void> updateCustomAlert({
    required String symbol,
    required double targetPrice,
    required bool enabled,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final symKey = symbol.toUpperCase();
      await prefs.setString('active_symbol', symKey);
      if (targetPrice > 0) {
        await prefs.setDouble('custom_target_price_$symKey', targetPrice);
      }
      await prefs.setBool('custom_price_alert_enabled_$symKey', enabled);

      try {
        FlutterForegroundTask.sendDataToTask({
          'activeSymbol': symKey,
        });
      } catch (_) {}

      try {
        final isRunning = await FlutterForegroundTask.isRunningService;
        if (isRunning) {
          _isServiceRunning = true;
        } else {
          await startService(symbol: symKey, targetPrice: targetPrice, enabled: enabled);
        }
      } catch (_) {
        await startService(symbol: symKey, targetPrice: targetPrice, enabled: enabled);
      }
    } catch (e) {
      debugPrint('[BackgroundService] updateCustomAlert error: $e');
    }
  }

  Future<bool> stopService() async {
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        try {
          await FlutterForegroundTask.stopService();
        } catch (_) {}
      }
      _isServiceRunning = false;
      return true;
    } catch (e) {
      debugPrint('[BackgroundService] stopService error: $e');
      return false;
    }
  }

  Future<bool> restartService({String symbol = 'XAUUSD', String serverUrl = ''}) async {
    try {
      await stopService();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return await startService(symbol: symbol, serverUrl: serverUrl);
    } catch (e) {
      debugPrint('[BackgroundService] restartService error: $e');
      return false;
    }
  }

  Future<bool> get isServiceActive async {
    try {
      final r = await FlutterForegroundTask.isRunningService;
      return r == true;
    } catch (_) {
      return false;
    }
  }
}
