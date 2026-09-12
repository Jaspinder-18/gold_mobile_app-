import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString('server_url') ?? 'https://gold-server-dbbq.onrender.com';
      _activeSymbol = prefs.getString('active_symbol') ?? 'XAUUSD';

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _notificationsPlugin.initialize(initSettings);
    } catch (e) {
      debugPrint('[BackgroundService] onStart error: $e');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString('server_url') ?? _serverUrl;
      _activeSymbol = prefs.getString('active_symbol') ?? _activeSymbol;

      final symKey = _activeSymbol.toUpperCase();
      final targetPrice = prefs.getDouble('custom_target_price_$symKey') ?? 0.0;
      final enabled = prefs.getBool('custom_price_alert_enabled_$symKey') ?? false;

      // 1. Fetch live market price directly from server in background task
      final cleanUrl = _serverUrl.replaceAll(RegExp(r'/+$'), '');
      final res = await http
          .get(Uri.parse('$cleanUrl/api/market/latest?symbol=$_activeSymbol'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final priceData = data['data'] ?? data;
        final currentPrice = double.tryParse(priceData['price']?.toString() ?? '0') ?? 0.0;

        if (currentPrice > 0) {
          // Keep foreground service notification updated with live market price
          FlutterForegroundTask.updateService(
            notificationTitle: '📊 $_activeSymbol · \$${currentPrice.toStringAsFixed(2)}',
            notificationText: enabled && targetPrice > 0
                ? 'Target: \$${targetPrice.toStringAsFixed(2)} · Live Alarm Guard Active'
                : 'Market Alert Monitor Active',
          );

          // 2. Evaluate price touch against active custom target
          if (enabled && targetPrice > 0) {
            const tolerance = 0.25;
            final diff = (currentPrice - targetPrice).abs();
            final isTouching = diff <= tolerance;
            final crossedUp = _previousPrice > 0 && _previousPrice < targetPrice && currentPrice >= targetPrice;
            final crossedDown = _previousPrice > 0 && _previousPrice > targetPrice && currentPrice <= targetPrice;

            if (isTouching || crossedUp || crossedDown) {
              debugPrint('[BackgroundService] 🚨 TARGET PRICE TOUCHED IN BACKGROUND: $_activeSymbol @ \$$currentPrice (Target: \$$targetPrice)');

              // Disarm in SharedPreferences to prevent repeated alarms
              await prefs.setBool('custom_price_alert_enabled_$symKey', false);

              // 3. Fire High-Priority System Alarm Notification with Loud Sound & Vibration
              final androidDetails = AndroidNotificationDetails(
                'gold_price_alerts_v5',
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
                  'Target: \$${targetPrice.toStringAsFixed(2)} · Custom Price Alert Triggered · Tap to view live chart',
                  contentTitle: '🚨 $_activeSymbol TOUCHED TARGET @ \$${currentPrice.toStringAsFixed(2)}',
                  summaryText: '$_activeSymbol Alert Terminal',
                ),
              );

              final notificationId = (_activeSymbol.hashCode ^ targetPrice.hashCode ^ DateTime.now().second).abs() % 100000;
              await _notificationsPlugin.show(
                notificationId,
                '🚨 $_activeSymbol TOUCHED TARGET @ \$${currentPrice.toStringAsFixed(2)}',
                'Target: \$${targetPrice.toStringAsFixed(2)} · Custom Price Alert Triggered',
                NotificationDetails(android: androidDetails),
                payload: 'alert_$notificationId',
              );
            }
          }
          _previousPrice = currentPrice;
        }
      }
    } catch (_) {
      // Safe blip ignore during network transitions
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isDestroyed) async {
    debugPrint('[BackgroundService] onDestroy: isDestroyed=$isDestroyed');
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['activeSymbol'] != null) _activeSymbol = map['activeSymbol'].toString();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  bool _isServiceRunning = false;
  bool get isRunning => _isServiceRunning;

  Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gold_bg_service_channel_silent',
        channelName: '📊 Background Market Service',
        channelDescription: 'Maintains live background connection for price monitoring',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // Check every 5s for rapid touch alerts
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // Register receive port
    FlutterForegroundTask.addTaskDataCallback((data) {
      debugPrint('[BackgroundService] Data received from background task: $data');
    });
  }

  Future<bool> startService({String symbol = 'XAUUSD', double targetPrice = 0.0, bool enabled = false}) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        _isServiceRunning = true;
        updateCustomAlert(symbol: symbol, targetPrice: targetPrice, enabled: enabled);
        return true;
      }

      final reqPermission = await FlutterForegroundTask.requestNotificationPermission();
      if (reqPermission == NotificationPermission.denied) {
        debugPrint('[BackgroundService] Notification permission denied');
      }

      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: '📊 ALERT Terminal Service Active',
        notificationText: enabled && targetPrice > 0
            ? '$symbol Target: \$${targetPrice.toStringAsFixed(2)} (Active Monitoring)'
            : '$symbol Live Market Monitoring Active',
        callback: startCallback,
      );

      _isServiceRunning = await FlutterForegroundTask.isRunningService;
      return _isServiceRunning;
    } catch (e) {
      debugPrint('[BackgroundService] startService error: $e');
      return false;
    }
  }

  Future<void> updateCustomAlert({required String symbol, required double targetPrice, required bool enabled}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_symbol', symbol);
      await prefs.setDouble('custom_target_price_${symbol.toUpperCase()}', targetPrice);
      await prefs.setBool('custom_price_alert_enabled_${symbol.toUpperCase()}', enabled);

      FlutterForegroundTask.sendDataToTask({
        'activeSymbol': symbol,
        'customTargetPrice': targetPrice,
        'customPriceAlertEnabled': enabled,
      });

      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.updateService(
          notificationTitle: '📊 $symbol Live Guard Active',
          notificationText: enabled && targetPrice > 0
              ? '$symbol Target: \$${targetPrice.toStringAsFixed(2)} (Active Alert Guard)'
              : '$symbol Live Feed Active',
        );
      }
    } catch (e) {
      debugPrint('[BackgroundService] updateCustomAlert error: $e');
    }
  }

  Future<bool> stopService() async {
    try {
      await FlutterForegroundTask.stopService();
      _isServiceRunning = await FlutterForegroundTask.isRunningService;
      return !_isServiceRunning;
    } catch (e) {
      debugPrint('[BackgroundService] stopService error: $e');
      return false;
    }
  }
}
