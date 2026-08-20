import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/market_data.dart';
import 'audio_service.dart';
import 'notification_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;
  String _serverUrl = 'https://gold-server-dbbq.onrender.com';
  bool _isConnected = false;

  MarketTick? currentTick;
  PivotConfig currentConfig = PivotConfig();
  List<AlertEvent> recentAlerts = [];
  Map<String, String> levelStates = {
    'R3': 'READY',
    'R2': 'READY',
    'S2': 'READY',
    'S3': 'READY',
  };

  // Callbacks
  Function(MarketTick)? onMarketTick;
  Function(AlertEvent)? onAlertTriggered;
  Function(bool)? onConnectionChange;
  Function(PivotConfig)? onConfigUpdate;
  Function(List<AlertEvent>)? onAlertsUpdate;
  Function(Map<String, String>)? onLevelStatesUpdate;

  bool get isConnected => _isConnected;
  String get serverUrl => _serverUrl;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('server_url') ?? 'https://gold-server-dbbq.onrender.com';
    await fetchInitialData();
    connectSocket();
  }

  Future<void> updateServerUrl(String newUrl) async {
    _serverUrl = newUrl.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _serverUrl);
    disconnectSocket();
    await fetchInitialData();
    connectSocket();
  }

  void connectSocket() {
    try {
      _socket?.dispose();
      _socket = io.io(
        _serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(9999)
            .setReconnectionDelay(1000)
            .build(),
      );

      _socket?.onConnect((_) {
        _isConnected = true;
        onConnectionChange?.call(true);
      });

      _socket?.onDisconnect((_) {
        _isConnected = false;
        onConnectionChange?.call(false);
      });

      _socket?.on('market_tick', (data) {
        if (data != null) {
          final map = Map<String, dynamic>.from(data);
          currentTick = MarketTick.fromJson(map);
          onMarketTick?.call(currentTick!);
        }
      });

      _socket?.on('initial_state', (data) {
        if (data != null) {
          final map = Map<String, dynamic>.from(data);
          if (map['market'] != null) {
            currentTick = MarketTick.fromJson(Map<String, dynamic>.from(map['market']));
            onMarketTick?.call(currentTick!);
          } else if (map['price'] != null) {
            currentTick = MarketTick.fromJson(map);
            onMarketTick?.call(currentTick!);
          }
          if (map['config'] != null) {
            currentConfig = PivotConfig.fromJson(Map<String, dynamic>.from(map['config']));
            onConfigUpdate?.call(currentConfig);
          }
          if (map['alertStates'] != null && map['alertStates'] is Map) {
            final states = Map<String, dynamic>.from(map['alertStates']);
            states.forEach((k, v) {
              if (v is Map && v['status'] != null) {
                levelStates[k] = v['status'].toString();
              }
            });
            onLevelStatesUpdate?.call(levelStates);
          }
        }
      });

      _socket?.on('config_updated', (data) {
        if (data != null) {
          final map = Map<String, dynamic>.from(data);
          currentConfig = PivotConfig.fromJson(map);
          onConfigUpdate?.call(currentConfig);
        }
      });

      _socket?.on('alert_triggered', (data) async {
        if (data != null) {
          final map = Map<String, dynamic>.from(data);
          final event = AlertEvent.fromJson(map);

          // Update level state color
          if (map['alertStates'] != null && map['alertStates'] is Map) {
            final states = Map<String, dynamic>.from(map['alertStates']);
            states.forEach((k, v) {
              if (v is Map && v['status'] != null) {
                levelStates[k] = v['status'].toString();
              }
            });
          } else {
            levelStates[event.level] = 'TRIGGERED';
          }
          onLevelStatesUpdate?.call(levelStates);

          // Update alerts list (strict 6 items)
          recentAlerts.insert(0, event);
          if (recentAlerts.length > 6) {
            recentAlerts = recentAlerts.sublist(0, 6);
          }
          onAlertsUpdate?.call(recentAlerts);
          onAlertTriggered?.call(event);

          // LOUD ALARM CLOCK / REMINDER ALERT SOUND
          await AudioService().playAlertSound();

          // PUSH NOTIFICATION WITH DIRECT CLICK TO SCREENSHOT
          await NotificationService().showAlertNotification(event);
        }
      });
    } catch (e) {
      _isConnected = false;
      onConnectionChange?.call(false);
    }
  }

  Future<bool> autoCalculatePivots() async {
    try {
      final res = await http.post(
        Uri.parse('$_serverUrl/api/config/auto-calculate'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null) {
          currentConfig = PivotConfig.fromJson(Map<String, dynamic>.from(body['data']));
          onConfigUpdate?.call(currentConfig);
          return true;
        }
      }
    } catch (e) {
      // Fallback
    }
    return false;
  }

  Future<bool> updateRemoteConfig(Map<String, dynamic> updates) async {
    try {
      final res = await http.put(
        Uri.parse('$_serverUrl/api/config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updates),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null) {
          currentConfig = PivotConfig.fromJson(Map<String, dynamic>.from(body['data']));
          onConfigUpdate?.call(currentConfig);
          return true;
        }
      }
    } catch (e) {
      // Ignore
    }
    return false;
  }

  void disconnectSocket() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    onConnectionChange?.call(false);
  }

  Future<void> fetchInitialData() async {
    try {
      // 1. Fetch Config
      final configRes = await http.get(Uri.parse('$_serverUrl/api/config')).timeout(const Duration(seconds: 5));
      if (configRes.statusCode == 200) {
        final body = json.decode(configRes.body);
        if (body['data'] != null) {
          currentConfig = PivotConfig.fromJson(Map<String, dynamic>.from(body['data']));
          onConfigUpdate?.call(currentConfig);
        }
      }

      // 2. Fetch Latest 6 Alerts
      final alertsRes = await http.get(Uri.parse('$_serverUrl/api/alerts?limit=6')).timeout(const Duration(seconds: 5));
      if (alertsRes.statusCode == 200) {
        final body = json.decode(alertsRes.body);
        if (body['data'] != null && body['data'] is List) {
          final list = (body['data'] as List).map((i) => AlertEvent.fromJson(Map<String, dynamic>.from(i))).toList();
          recentAlerts = list.take(6).toList();
          onAlertsUpdate?.call(recentAlerts);
        }
      }

      // 3. Fetch Ticker
      final tickerRes = await http.get(Uri.parse('$_serverUrl/api/market/ticker')).timeout(const Duration(seconds: 5));
      if (tickerRes.statusCode == 200) {
        final body = json.decode(tickerRes.body);
        if (body['data'] != null) {
          currentTick = MarketTick.fromJson(Map<String, dynamic>.from(body['data']));
          onMarketTick?.call(currentTick!);
        }
      }
    } catch (e) {
      // Ignore network delays
    }
  }

  Future<AlertEvent?> captureScreenshot({
    String timeframe = '15',
    String range = '1D',
    int barSpacing = 22,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_serverUrl/api/test/capture-screenshot'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'level': 'MANUAL',
          'timeframe': timeframe,
          'range': range,
          'barSpacing': barSpacing,
        }),
      ).timeout(const Duration(seconds: 40));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null) {
          final event = AlertEvent.fromJson(Map<String, dynamic>.from(body['data']));
          recentAlerts.insert(0, event);
          if (recentAlerts.length > 6) {
            recentAlerts = recentAlerts.sublist(0, 6);
          }
          onAlertsUpdate?.call(recentAlerts);
          return event;
        }
      }
    } catch (e) {
      // Error
    }
    return null;
  }

  Future<bool> deleteAlert(String id) async {
    try {
      final res = await http.delete(Uri.parse('$_serverUrl/api/alerts/$id')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        recentAlerts.removeWhere((a) => a.id == id);
        onAlertsUpdate?.call(recentAlerts);
        return true;
      }
    } catch (e) {
      // Error
    }
    return false;
  }
}
