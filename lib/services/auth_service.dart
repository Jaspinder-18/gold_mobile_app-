import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

  static const String _prefUserKey = 'auth_user_profile_json';
  static const String _prefTokenKey = 'auth_session_token';

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

  /// Load persisted session from local disk
  Future<bool> loadSavedSession() async {
    if (_isInitialized) return isLoggedIn;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawUser = prefs.getString(_prefUserKey);
      final sessionToken = prefs.getString(_prefTokenKey);

      if (rawUser != null && rawUser.isNotEmpty) {
        final data = json.decode(rawUser);
        _currentUser = UserModel.fromJson(data, sessionToken: sessionToken);
        debugPrint('[AuthService] Restored active session for: ${_currentUser?.email}');

        // Silent FCM token sync in background
        _syncTokenInBackground();
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

      final response = await http.post(
        Uri.parse('$cleanUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fullName': fullName.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'confirmPassword': confirmPassword,
          'fcmToken': fcmToken,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
          'deviceName': defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone / iPad' : 'Android Device',
        }),
      ).timeout(const Duration(seconds: 12));

      final body = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && body['success'] == true) {
        final userData = body['data']?['user'] ?? body['data'];
        final sessionToken = body['data']?['token']?.toString();

        _currentUser = UserModel.fromJson(userData, sessionToken: sessionToken);
        await _persistSession(_currentUser!, sessionToken);

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

      final response = await http.post(
        Uri.parse('$cleanUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email.trim().toLowerCase(),
          'password': password,
          'fcmToken': fcmToken,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
          'deviceName': defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone / iPad' : 'Android Device',
        }),
      ).timeout(const Duration(seconds: 12));

      final body = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && body['success'] == true) {
        final userData = body['data']?['user'] ?? body['data'];
        final sessionToken = body['data']?['token']?.toString();

        _currentUser = UserModel.fromJson(userData, sessionToken: sessionToken);
        await _persistSession(_currentUser!, sessionToken);

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

  /// Logout from current device
  Future<void> logout() async {
    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final fcmToken = await _getFcmTokenSafely();

      if (_currentUser != null) {
        try {
          await http.post(
            Uri.parse('$cleanUrl/api/auth/logout'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': _currentUser!.email,
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

  Future<void> _persistSession(UserModel user, String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUserKey, json.encode(user.toJson()));
      if (token != null) {
        await prefs.setString(_prefTokenKey, token);
      }
    } catch (_) {}
  }

  Future<void> _syncTokenInBackground() async {
    if (_currentUser == null) return;
    try {
      final token = await _getFcmTokenSafely();
      if (token != null && token.isNotEmpty) {
        final serverUrl = await _resolveServerUrl();
        final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
        await http.post(
          Uri.parse('$cleanUrl/api/auth/fcm-sync'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'email': _currentUser!.email,
            'fcmToken': token,
            'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
            'deviceName': defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone / iPad' : 'Android Device',
          }),
        ).timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
  }
}
