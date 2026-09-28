import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/user_model.dart';
import 'notification_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  UserModel? _currentUser;
  bool _isInitialized = false;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isInitialized => _isInitialized;
  String? get sessionToken => _currentUser?.sessionToken;

  static const String _prefUserKey = 'auth_user_profile_json';
  static const String _prefTokenKey = 'auth_session_token';
  static const String _prefDeviceIdKey = 'gold_mobile_device_id';

  Future<String> _resolveServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('server_url');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        return savedUrl.trim();
      }
    } catch (_) {}
    return 'https://gold-server-dbbq.onrender.com';
  }

  Future<String?> _getFcmTokenSafely() async {
    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 4));
      return token;
    } catch (_) {
      return NotificationService().fcmToken;
    }
  }

  /// Get or create a persistent unique deviceId for this phone
  Future<String> getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_prefDeviceIdKey);
      if (existing != null && existing.isNotEmpty) {
        return existing;
      }

      String id = '';
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        id = 'android_${androidInfo.id}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        id = 'ios_${iosInfo.identifierForVendor ?? DateTime.now().millisecondsSinceEpoch}';
      }

      if (id.isEmpty || id.contains('unknown')) {
        id = 'mob_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecondsSinceEpoch % 100000)}';
      }

      await prefs.setString(_prefDeviceIdKey, id);
      return id;
    } catch (_) {
      return 'mob_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Get human-friendly model or device name
  Future<String> getDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        final brand = androidInfo.brand;
        final model = androidInfo.model;
        if (brand.isNotEmpty && model.isNotEmpty) {
          final brandCap = brand[0].toUpperCase() + brand.substring(1);
          return model.toLowerCase().contains(brand.toLowerCase()) ? model : '$brandCap $model';
        }
        return 'Android Device';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.name.isNotEmpty ? iosInfo.name : 'Apple iPhone';
      }
    } catch (_) {}
    return defaultTargetPlatform == TargetPlatform.iOS ? 'Apple iPhone' : 'Android Device';
  }

  /// Load persisted session from local disk
  Future<bool> loadSavedSession() async {
    if (_isInitialized) return isLoggedIn;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawUser = prefs.getString(_prefUserKey);
      final savedToken = prefs.getString(_prefTokenKey);

      if (rawUser != null && rawUser.isNotEmpty) {
        final data = json.decode(rawUser);
        _currentUser = UserModel.fromJson(data, sessionToken: savedToken);
        debugPrint('[AuthService] Restored active session for: ${_currentUser?.email}');

        // Silent device registration & FCM sync in background
        registerDeviceWithBackend();
      }
    } catch (e) {
      debugPrint('[AuthService] Error loading saved session: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
    return isLoggedIn;
  }

  /// Register new user account
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final fcmToken = await _getFcmTokenSafely();
      final deviceId = await getDeviceId();
      final deviceName = await getDeviceName();

      final response = await http.post(
        Uri.parse('$cleanUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fullName': fullName.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'confirmPassword': confirmPassword,
          'fcmToken': fcmToken,
          'deviceId': deviceId,
          'deviceName': deviceName,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
        }),
      ).timeout(const Duration(seconds: 12));

      final body = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && body['success'] == true) {
        final userData = body['data']?['user'] ?? body['data'];
        final savedToken = body['data']?['token']?.toString();

        _currentUser = UserModel.fromJson(userData, sessionToken: savedToken);
        await _persistSession(_currentUser!, savedToken);

        // Register device
        await registerDeviceWithBackend();

        notifyListeners();
        return {'success': true, 'message': body['message'] ?? 'Account created successfully!'};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Registration failed. Please check details.'};
      }
    } catch (e) {
      debugPrint('[AuthService] Registration exception: $e');
      return {'success': false, 'error': 'Network connection error. Please verify server connectivity.'};
    }
  }

  /// Login user
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final fcmToken = await _getFcmTokenSafely();
      final deviceId = await getDeviceId();
      final deviceName = await getDeviceName();

      final response = await http.post(
        Uri.parse('$cleanUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email.trim().toLowerCase(),
          'password': password,
          'fcmToken': fcmToken,
          'deviceId': deviceId,
          'deviceName': deviceName,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
        }),
      ).timeout(const Duration(seconds: 12));

      final body = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && body['success'] == true) {
        final userData = body['data']?['user'] ?? body['data'];
        final savedToken = body['data']?['token']?.toString();

        _currentUser = UserModel.fromJson(userData, sessionToken: savedToken);
        await _persistSession(_currentUser!, savedToken);

        // Link device
        await registerDeviceWithBackend();

        notifyListeners();
        return {'success': true, 'message': body['message'] ?? 'Logged in successfully!'};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Invalid email or password.'};
      }
    } catch (e) {
      debugPrint('[AuthService] Login exception: $e');
      return {'success': false, 'error': 'Network connection error. Please verify server connectivity.'};
    }
  }

  /// Logout from current device only
  Future<void> logout() async {
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final fcmToken = await _getFcmTokenSafely();
      final deviceId = await getDeviceId();
      final token = sessionToken;

      if (_currentUser != null) {
        try {
          await http.post(
            Uri.parse('$cleanUrl/api/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'email': _currentUser!.email,
              'deviceId': deviceId,
              'fcmToken': fcmToken,
            }),
          ).timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefUserKey);
      await prefs.remove(_prefTokenKey);
    } catch (e) {
      debugPrint('[AuthService] Logout cleanup note: $e');
    } finally {
      _currentUser = null;
      notifyListeners();
    }
  }

  /// Reset Password
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');

      final response = await http.post(
        Uri.parse('$cleanUrl/api/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email.trim().toLowerCase(),
          'newPassword': newPassword,
          'confirmPassword': confirmPassword,
        }),
      ).timeout(const Duration(seconds: 12));

      final body = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && body['success'] == true) {
        final userData = body['data']?['user'] ?? body['data'];
        final savedToken = body['data']?['token']?.toString();

        _currentUser = UserModel.fromJson(userData, sessionToken: savedToken);
        await _persistSession(_currentUser!, savedToken);
        await registerDeviceWithBackend();

        notifyListeners();
        return {'success': true, 'message': body['message'] ?? 'Password reset successfully!'};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Reset password failed.'};
      }
    } catch (e) {
      debugPrint('[AuthService] Reset password exception: $e');
      return {'success': false, 'error': 'Network connection error. Please verify server connectivity.'};
    }
  }

  Future<void> _persistSession(UserModel user, String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUserKey, json.encode(user.toJson()));
      if (token != null) {
        await prefs.setString(_prefTokenKey, token);
      }
    } catch (_) {}
  }

  /// Register or update this device on the server
  Future<bool> registerDeviceWithBackend() async {
    if (_currentUser == null) return false;
    try {
      final token = sessionToken;
      final fcmToken = await _getFcmTokenSafely();
      if (fcmToken == null || fcmToken.isEmpty) return false;

      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final deviceId = await getDeviceId();
      final deviceName = await getDeviceName();

      final prefs = await SharedPreferences.getInstance();
      final notifyEnabled = prefs.getBool('notifications_enabled') ?? true;

      final response = await http.post(
        Uri.parse('$cleanUrl/api/devices/register'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'deviceId': deviceId,
          'fcmToken': fcmToken,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
          'deviceName': deviceName,
          'notificationsEnabled': notifyEnabled,
        }),
      ).timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[AuthService] registerDeviceWithBackend error: $e');
      return false;
    }
  }

  /// Get connected devices for the authenticated user
  Future<List<Map<String, dynamic>>> getConnectedDevices() async {
    if (_currentUser == null) return [];
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final currentDeviceId = await getDeviceId();
      final token = sessionToken;

      final response = await http.get(
        Uri.parse('$cleanUrl/api/devices'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = json.decode(response.body);
        if (body['success'] == true && body['data'] is List) {
          return (body['data'] as List).map((d) {
            final map = Map<String, dynamic>.from(d);
            map['isCurrentDevice'] = (map['deviceId'] == currentDeviceId);
            return map;
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('[AuthService] getConnectedDevices error: $e');
    }
    return [];
  }

  /// Toggle notification setting for a specific device
  Future<bool> updateDeviceNotifications(String targetDeviceId, bool enabled) async {
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final token = sessionToken;

      final response = await http.put(
        Uri.parse('$cleanUrl/api/devices/$targetDeviceId/notifications'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'enabled': enabled}),
      ).timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[AuthService] updateDeviceNotifications error: $e');
      return false;
    }
  }

  /// Unlink / remove a device from the account
  Future<bool> removeDevice(String targetDeviceId) async {
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final token = sessionToken;

      final response = await http.delete(
        Uri.parse('$cleanUrl/api/devices/$targetDeviceId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[AuthService] removeDevice error: $e');
      return false;
    }
  }

  /// Send a test push notification to a specific device
  Future<bool> sendDeviceTestPush(String targetDeviceId) async {
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final token = sessionToken;

      final response = await http.post(
        Uri.parse('$cleanUrl/api/devices/test-push'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'deviceId': targetDeviceId}),
      ).timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[AuthService] sendDeviceTestPush error: $e');
      return false;
    }
  }

  /// Toggle overall user notification preferences on server & locally
  Future<bool> updateNotificationPreferences(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', enabled);

      if (_currentUser != null) {
        _currentUser = UserModel(
          id: _currentUser!.id,
          fullName: _currentUser!.fullName,
          email: _currentUser!.email,
          role: _currentUser!.role,
          activeDevicesCount: _currentUser!.activeDevicesCount,
          token: _currentUser!.token,
          notificationsEnabled: enabled,
        );
        await _persistSession(_currentUser!, _currentUser!.token);
        notifyListeners();

        // Also update the current device record on backend
        final currentDeviceId = await getDeviceId();
        await updateDeviceNotifications(currentDeviceId, enabled);
      }
      return true;
    } catch (e) {
      debugPrint('[AuthService] updateNotificationPreferences error: $e');
      return false;
    }
  }
}
