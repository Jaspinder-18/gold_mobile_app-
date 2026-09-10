import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MarketAlertTaskHandler());
}

class MarketAlertTaskHandler extends TaskHandler {
  String _serverUrl = 'https://gold-server-dbbq.onrender.com';
  String _activeSymbol = 'XAUUSD';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString('server_url') ?? 'https://gold-server-dbbq.onrender.com';
      _activeSymbol = prefs.getString('active_symbol') ?? 'XAUUSD';
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

      // Keep foreground notification refreshed with active symbol
      FlutterForegroundTask.updateService(
        notificationTitle: '📊 Gold & Multi-Asset Terminal',
        notificationText: '$_activeSymbol · Real-time market data & Firebase alerts active',
      );
    } catch (_) {
      // Safe blip ignore
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
