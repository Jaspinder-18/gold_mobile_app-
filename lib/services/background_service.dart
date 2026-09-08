import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MarketAlertTaskHandler());
}

class MarketAlertTaskHandler extends TaskHandler {
  String _serverUrl = 'https://gold-server-dbbq.onrender.com';
  String _activeSymbol = 'XAUUSD';
  double _customTargetPrice = 0.0;
  bool _customPriceAlertEnabled = false;
  double _lastPrice = 0.0;
  int _lastAlertTimestamp = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString('server_url') ?? 'https://gold-server-dbbq.onrender.com';
      _activeSymbol = prefs.getString('active_symbol') ?? 'XAUUSD';
      _customPriceAlertEnabled = prefs.getBool('custom_price_alert_enabled_${_activeSymbol.toUpperCase()}') ?? false;
      _customTargetPrice = prefs.getDouble('custom_target_price_${_activeSymbol.toUpperCase()}') ?? 0.0;
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
      final cachedEnabled = prefs.getBool('custom_price_alert_enabled_${_activeSymbol.toUpperCase()}');
      final cachedTarget = prefs.getDouble('custom_target_price_${_activeSymbol.toUpperCase()}');

      if (cachedEnabled != null) _customPriceAlertEnabled = cachedEnabled;
      if (cachedTarget != null) _customTargetPrice = cachedTarget;

      // 1. Fetch live market price and custom alert state from backend server
      final res = await http.get(
        Uri.parse('$_serverUrl/api/market/ticker?symbol=$_activeSymbol'),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data != null && data['data'] != null) {
          final tickMap = Map<String, dynamic>.from(data['data']);
          final currentPrice = (tickMap['price'] is num) ? (tickMap['price'] as num).toDouble() : (double.tryParse(tickMap['price'].toString()) ?? 0.0);

          if (currentPrice > 0) {
            final prevPrice = _lastPrice > 0 ? _lastPrice : currentPrice;
            _lastPrice = currentPrice;

            // Update foreground service notification text with live price
            final notifText = _customPriceAlertEnabled && _customTargetPrice > 0
                ? '$_activeSymbol: \$${currentPrice.toStringAsFixed(2)} · Target: \$${_customTargetPrice.toStringAsFixed(2)} (ACTIVE)'
                : '$_activeSymbol: \$${currentPrice.toStringAsFixed(2)} · Live Market Feed Active';

            FlutterForegroundTask.updateService(
              notificationTitle: '🚨 Gold & Multi-Asset Terminal',
              notificationText: notifText,
            );

            // 2. Evaluate custom price touch in background
            if (_customPriceAlertEnabled && _customTargetPrice > 0) {
              final tolerance = 0.20;
              final isTouching = (currentPrice - _customTargetPrice).abs() <= tolerance;
              final crossedUp = prevPrice < _customTargetPrice && currentPrice >= _customTargetPrice;
              final crossedDown = prevPrice > _customTargetPrice && currentPrice <= _customTargetPrice;

              if (isTouching || crossedUp || crossedDown) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - _lastAlertTimestamp > 15000) {
                  _lastAlertTimestamp = now;
                  _customPriceAlertEnabled = false;

                  await prefs.setBool('custom_price_alert_enabled_${_activeSymbol.toUpperCase()}', false);

                  // Update foreground notification banner to TRIGGERED immediately
                  FlutterForegroundTask.updateService(
                    notificationTitle: '🚨 TARGET TOUCHED: $_activeSymbol @ \$${currentPrice.toStringAsFixed(2)}',
                    notificationText: 'Custom Target \$${_customTargetPrice.toStringAsFixed(2)} REACHED! Tap to view.',
                  );

                  // Send data to main UI isolate if attached
                  FlutterForegroundTask.sendDataToMain({
                    'type': 'ALERT_TRIGGERED',
                    'symbol': _activeSymbol,
                    'targetPrice': _customTargetPrice,
                    'currentPrice': currentPrice,
                    'timestamp': now,
                  });
                }
              }
            }
          }
        }
      }
    } catch (e) {
      // Network timeout / connection blip handled safely
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
      if (map['customTargetPrice'] != null) {
        _customTargetPrice = (map['customTargetPrice'] as num).toDouble();
      }
      if (map['customPriceAlertEnabled'] != null) {
        _customPriceAlertEnabled = map['customPriceAlertEnabled'] == true;
      }
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
        channelId: 'gold_alarm_channel_v4',
        channelName: '🚨 High Priority Price Level Alarms',
        channelDescription: 'Real-time background price monitoring and high priority custom price alerts',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: true,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(3000), // Check every 3s in background
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
        notificationTitle: '🚨 Gold & Multi-Asset Terminal',
        notificationText: enabled && targetPrice > 0
            ? '$symbol Target: \$${targetPrice.toStringAsFixed(2)} (ACTIVE MONITORING)'
            : 'Live Market Monitoring Active',
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
          notificationTitle: '🚨 Gold & Multi-Asset Terminal',
          notificationText: enabled && targetPrice > 0
              ? '$symbol Target: \$${targetPrice.toStringAsFixed(2)} (ACTIVE MONITORING)'
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
