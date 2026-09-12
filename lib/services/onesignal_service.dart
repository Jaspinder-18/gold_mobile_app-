import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class OneSignalService {
  static final OneSignalService _instance = OneSignalService._internal();
  factory OneSignalService() => _instance;
  OneSignalService._internal();

  bool _isInitialized = false;
  String? _appId;

  String? get appId => _appId;
  bool get isInitialized => _isInitialized;

  // Placeholder or configured App ID
  static const String defaultAppId = '';

  Future<void> initialize({String? customAppId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _appId = customAppId ?? prefs.getString('onesignal_app_id') ?? defaultAppId;

      if (_appId == null || _appId!.trim().isEmpty) {
        debugPrint('[OneSignalService] Notice: OneSignal App ID is not yet configured.');
        return;
      }

      OneSignal.Debug.setLogLevel(kDebugMode ? OSLogLevel.verbose : OSLogLevel.none);
      OneSignal.initialize(_appId!.trim());

      // Request Push Notification Permission
      final granted = await OneSignal.Notifications.requestPermission(true);
      debugPrint('[OneSignalService] Notification permission granted: $granted');

      // Click listener for closed / background app
      OneSignal.Notifications.addClickListener((event) {
        debugPrint('[OneSignalService] Notification clicked: ${event.notification.additionalData}');
        final data = event.notification.additionalData;
        final payload = data?['screenshotUrl'] ?? data?['alertId'];
        if (payload != null) {
          NotificationService().onNotificationTap?.call(payload.toString());
        }
      });

      // Foreground display listener
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        debugPrint('[OneSignalService] Foreground notification received: ${event.notification.title}');
        event.notification.display();
      });

      _isInitialized = true;
      debugPrint('[OneSignalService] ✓ OneSignal initialized with App ID: $_appId');
    } catch (e) {
      debugPrint('[OneSignalService] initialize error: $e');
    }
  }

  Future<void> setAppId(String newAppId) async {
    final clean = newAppId.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onesignal_app_id', clean);
    _appId = clean;
    await initialize(customAppId: clean);
  }
}
