import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/market_data.dart';
import 'audio_service.dart';
import 'notification_service.dart';

class SocketService with WidgetsBindingObserver {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  static SocketService get instance => _instance;
  
  SocketService._internal() {
    WidgetsBinding.instance.addObserver(this);
    // Continuous live sync timer: checks socket health & polls latest price every 2.5 seconds
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _checkHealthAndSync();
    });
  }

  io.Socket? _socket;
  String _serverUrl = 'https://gold-server-dbbq.onrender.com';
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  bool _isPollingPrice = false;

  // Anti-duplicate alert debounce cache: debounceKey -> timestamp
  final Map<String, int> _recentAlertTimestamps = {};

  MarketTick? currentTick;
  PivotConfig currentConfig = PivotConfig();
  SymbolModel? activeSymbolConfig;
  PivotStateModel? activePivotState;
  String activeSymbol = 'XAUUSD';
  List<AlertEvent> recentAlerts = [];
  List<PriceAlertModel> activeAlerts = [];
  Map<String, String> levelStates = {
    'R3': 'READY',
    'R2': 'READY',
    'S2': 'READY',
    'S3': 'READY',
    'CUSTOM': 'READY',
  };

  // Multi-subscriber listener pools (prevents one screen from overwriting another)
  final Set<Function(MarketTick)> _marketTickListeners = {};
  final Set<Function(AlertEvent)> _alertTriggeredListeners = {};
  final Set<Function(bool)> _connectionListeners = {};
  final Set<Function(PivotConfig)> _configListeners = {};
  final Set<Function(List<AlertEvent>)> _alertsListeners = {};
  final Set<Function(List<PriceAlertModel>)> _activeAlertsListeners = {};
  final Set<Function(Map<String, String>)> _levelStatesListeners = {};
  final Set<Function(String, SymbolModel?, PivotStateModel?)> _symbolListeners = {};

  // Setter properties for backward compatibility (adds to listener pool)
  set onMarketTick(Function(MarketTick)? fn) {
    if (fn != null) _marketTickListeners.add(fn);
  }
  set onAlertTriggered(Function(AlertEvent)? fn) {
    if (fn != null) _alertTriggeredListeners.add(fn);
  }
  set onConnectionChange(Function(bool)? fn) {
    if (fn != null) _connectionListeners.add(fn);
  }
  set onConfigUpdate(Function(PivotConfig)? fn) {
    if (fn != null) _configListeners.add(fn);
  }
  set onAlertsUpdate(Function(List<AlertEvent>)? fn) {
    if (fn != null) _alertsListeners.add(fn);
  }
  set onActiveAlertsUpdate(Function(List<PriceAlertModel>)? fn) {
    if (fn != null) _activeAlertsListeners.add(fn);
  }
  set onLevelStatesUpdate(Function(Map<String, String>)? fn) {
    if (fn != null) _levelStatesListeners.add(fn);
  }
  set onSymbolUpdate(Function(String, SymbolModel?, PivotStateModel?)? fn) {
    if (fn != null) _symbolListeners.add(fn);
  }

  void addMarketTickListener(Function(MarketTick) fn) => _marketTickListeners.add(fn);
  void removeMarketTickListener(Function(MarketTick) fn) => _marketTickListeners.remove(fn);

  void addConfigListener(Function(PivotConfig) fn) => _configListeners.add(fn);
  void removeConfigListener(Function(PivotConfig) fn) => _configListeners.remove(fn);

  void addActiveAlertsListener(Function(List<PriceAlertModel>) fn) => _activeAlertsListeners.add(fn);
  void removeActiveAlertsListener(Function(List<PriceAlertModel>) fn) => _activeAlertsListeners.remove(fn);

  void addAlertsListener(Function(List<AlertEvent>) fn) => _alertsListeners.add(fn);
  void removeAlertsListener(Function(List<AlertEvent>) fn) => _alertsListeners.remove(fn);

  void _dispatchMarketTick(MarketTick tick) {
    currentTick = tick;
    for (final fn in _marketTickListeners.toList()) {
      try { fn(tick); } catch (_) {}
    }
  }

  void _dispatchConnectionChange(bool connected) {
    _isConnected = connected;
    for (final fn in _connectionListeners.toList()) {
      try { fn(connected); } catch (_) {}
    }
  }

  void _dispatchConfigUpdate(PivotConfig config) {
    currentConfig = config;
    for (final fn in _configListeners.toList()) {
      try { fn(config); } catch (_) {}
    }
  }

  void _dispatchAlertsUpdate(List<AlertEvent> alerts) {
    recentAlerts = alerts;
    for (final fn in _alertsListeners.toList()) {
      try { fn(alerts); } catch (_) {}
    }
  }

  void _dispatchActiveAlertsUpdate(List<PriceAlertModel> alerts) {
    activeAlerts = alerts;
    for (final fn in _activeAlertsListeners.toList()) {
      try { fn(alerts); } catch (_) {}
    }
  }

  void _dispatchLevelStatesUpdate(Map<String, String> states) {
    for (final fn in _levelStatesListeners.toList()) {
      try { fn(states); } catch (_) {}
    }
  }

  void _dispatchSymbolUpdate(String symbol, SymbolModel? symConfig, PivotStateModel? pivotState) {
    for (final fn in _symbolListeners.toList()) {
      try { fn(symbol, symConfig, pivotState); } catch (_) {}
    }
  }

  void _dispatchAlertTriggered(AlertEvent event) {
    for (final fn in _alertTriggeredListeners.toList()) {
      try { fn(event); } catch (_) {}
    }
  }

  bool get isConnected => _isConnected;
  String get serverUrl => _serverUrl;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkHealthAndSync();
      fetchInitialData();
    }
  }

  void _checkHealthAndSync() {
    if (_socket == null || !_isConnected || !(_socket!.connected)) {
      connectSocket();
    }
    // High-reliability live price fallback poll
    _pollLatestPriceFallback();
    _syncLatestAlertsFromBackend();
  }

  /// High-reliability continuous live price poll from backend REST endpoint
  Future<void> _pollLatestPriceFallback() async {
    if (_isPollingPrice) return;
    _isPollingPrice = true;
    try {
      final res = await http.get(Uri.parse('$_serverUrl/api/market/ticker')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null) {
          final tick = MarketTick.fromJson(Map<String, dynamic>.from(body['data']));
          if (tick.price > 0) {
            _dispatchMarketTick(tick);
            if (!_isConnected) {
              _dispatchConnectionChange(true);
            }
          }
        }
      }
    } catch (_) {} finally {
      _isPollingPrice = false;
    }
  }

  /// Background sync to ensure alerts are up-to-date
  Future<void> _syncLatestAlertsFromBackend() async {
    try {
      final alertsRes = await http.get(Uri.parse('$_serverUrl/api/alerts?limit=6')).timeout(const Duration(seconds: 4));
      if (alertsRes.statusCode == 200) {
        final body = json.decode(alertsRes.body);
        if (body['data'] != null && body['data'] is List) {
          final list = (body['data'] as List).map((i) => AlertEvent.fromJson(Map<String, dynamic>.from(i))).toList();
          if (list.isNotEmpty) {
            _dispatchAlertsUpdate(list.take(6).toList());
          }
        }
      }
    } catch (_) {}
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('server_url') ?? 'https://gold-server-dbbq.onrender.com';

    await NotificationService().initialize(serverUrl: _serverUrl);
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

    // Re-register FCM token with new server URL
    final fcmToken = NotificationService().fcmToken;
    if (fcmToken != null) {
      NotificationService().registerTokenWithServer(_serverUrl, fcmToken);
    }
  }

  void connectSocket() {
    try {
      _socket?.dispose();

      debugPrint('[SocketService] Connecting to $_serverUrl...');

      _socket = io.io(
        _serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(9999)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(3000)
            .setTimeout(6000)
            .build(),
      );

      _socket?.onConnect((_) {
        debugPrint('[SocketService] ✓ Connected to Socket.IO Server');
        _dispatchConnectionChange(true);

        // Register FCM token with server upon connection
        final fcmToken = NotificationService().fcmToken;
        if (fcmToken != null) {
          NotificationService().registerTokenWithServer(_serverUrl, fcmToken);
        }
      });

      _socket?.onDisconnect((_) {
        debugPrint('[SocketService] ✕ Disconnected from Socket.IO Server');
        _dispatchConnectionChange(false);
      });

      _socket?.onConnectError((err) {
        debugPrint('[SocketService] Connection Error: $err');
        _dispatchConnectionChange(false);
      });

      _socket?.onError((err) {
        debugPrint('[SocketService] Socket Error: $err');
      });

      void handleTick(dynamic data) {
        if (data != null) {
          try {
            final map = Map<String, dynamic>.from(data as Map);
            final tick = MarketTick.fromJson(map);
            _dispatchMarketTick(tick);
          } catch (e) {
            debugPrint('[SocketService] handleTick error: $e');
          }
        }
      }
      _socket?.on('market_tick', handleTick);
      _socket?.on('market:tick', handleTick);

      void handleInitial(dynamic data) {
        if (data != null) {
          try {
            final map = Map<String, dynamic>.from(data as Map);
            if (map['activeSymbol'] != null) {
              activeSymbol = map['activeSymbol'].toString();
            }
            if (map['symbolConfig'] != null) {
              activeSymbolConfig = SymbolModel.fromJson(Map<String, dynamic>.from(map['symbolConfig'] as Map));
            }
            if (map['pivotState'] != null) {
              activePivotState = PivotStateModel.fromJson(Map<String, dynamic>.from(map['pivotState'] as Map));
            }
            if (map['market'] != null) {
              final tick = MarketTick.fromJson(Map<String, dynamic>.from(map['market'] as Map));
              _dispatchMarketTick(tick);
            } else if (map['price'] != null) {
              final tick = MarketTick.fromJson(map);
              _dispatchMarketTick(tick);
            }
            if (map['config'] != null) {
              currentConfig = PivotConfig.fromJson(Map<String, dynamic>.from(map['config'] as Map));
              _dispatchConfigUpdate(currentConfig);
            }
            if (map['activeAlerts'] != null && map['activeAlerts'] is List) {
              activeAlerts = (map['activeAlerts'] as List)
                  .map((i) => PriceAlertModel.fromJson(Map<String, dynamic>.from(i as Map)))
                  .toList();
              _dispatchActiveAlertsUpdate(activeAlerts);
            }
            if (map['alertStates'] != null && map['alertStates'] is Map) {
              final states = Map<String, dynamic>.from(map['alertStates'] as Map);
              states.forEach((k, v) {
                if (v is Map && v['status'] != null) {
                  levelStates[k] = v['status'].toString();
                } else if (v != null) {
                  levelStates[k] = v.toString();
                }
              });
              _dispatchLevelStatesUpdate(levelStates);
            }
            _dispatchSymbolUpdate(activeSymbol, activeSymbolConfig, activePivotState);
          } catch (e) {
            debugPrint('[SocketService] handleInitial error: $e');
          }
        }
      }
      _socket?.on('initial_state', handleInitial);
      _socket?.on('initial:state', handleInitial);

      _socket?.on('symbol:active', (data) {
        if (data != null) {
          try {
            final map = Map<String, dynamic>.from(data as Map);
            if (map['symbol'] != null) activeSymbol = map['symbol'].toString();
            if (map['config'] != null) activeSymbolConfig = SymbolModel.fromJson(Map<String, dynamic>.from(map['config'] as Map));
            if (map['pivotState'] != null) activePivotState = PivotStateModel.fromJson(Map<String, dynamic>.from(map['pivotState'] as Map));
            if (map['market'] != null) {
              final tick = MarketTick.fromJson(Map<String, dynamic>.from(map['market'] as Map));
              _dispatchMarketTick(tick);
            }
            if (map['activeAlerts'] != null && map['activeAlerts'] is List) {
              activeAlerts = (map['activeAlerts'] as List)
                  .map((i) => PriceAlertModel.fromJson(Map<String, dynamic>.from(i as Map)))
                  .toList();
              _dispatchActiveAlertsUpdate(activeAlerts);
            }
            _dispatchSymbolUpdate(activeSymbol, activeSymbolConfig, activePivotState);
          } catch (e) {
            debugPrint('[SocketService] symbol:active error: $e');
          }
        }
      });

      void handleConfig(dynamic data) {
        if (data != null) {
          try {
            final map = Map<String, dynamic>.from(data as Map);
            currentConfig = PivotConfig.fromJson(map);
            _dispatchConfigUpdate(currentConfig);
          } catch (e) {
            debugPrint('[SocketService] config_updated error: $e');
          }
        }
      }
      _socket?.on('config_updated', handleConfig);
      _socket?.on('config:update', handleConfig);

      // Multi-Alert List Updates
      void handleAlertListUpdated(dynamic data) {
        if (data != null && data is Map) {
          try {
            final map = Map<String, dynamic>.from(data);
            final sym = map['symbol']?.toString();
            if (sym != null && sym.toUpperCase() != activeSymbol.toUpperCase()) return;

            if (map['activeAlerts'] != null && map['activeAlerts'] is List) {
              activeAlerts = (map['activeAlerts'] as List)
                  .map((i) => PriceAlertModel.fromJson(Map<String, dynamic>.from(i as Map)))
                  .toList();
              _dispatchActiveAlertsUpdate(activeAlerts);
            } else {
              fetchActiveAlerts();
            }
          } catch (e) {
            debugPrint('[SocketService] handleAlertListUpdated error: $e');
          }
        }
      }
      _socket?.on('custom_alert:list_updated', handleAlertListUpdated);
      _socket?.on('custom_alert:created', handleAlertListUpdated);
      _socket?.on('custom_alert:deleted', handleAlertListUpdated);
      _socket?.on('custom_alert:removed', handleAlertListUpdated);

      // Single authoritative alert trigger handler
      void handleIncomingAlert(dynamic data) async {
        if (data == null) return;
        try {
          final Map<String, dynamic> map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
          final Map<String, dynamic> eventMap = (map['event'] != null && map['event'] is Map)
              ? Map<String, dynamic>.from(map['event'] as Map)
              : map;

          if (eventMap.isEmpty) return;

          final event = AlertEvent.fromJson(eventMap);
          final now = DateTime.now().millisecondsSinceEpoch;
          final alertAgeMs = (now - event.timestamp.millisecondsSinceEpoch).abs();

          // Reject historical or stale alert events (older than 20 seconds) unless it's a direct manual test
          if (alertAgeMs > 20000 && !event.isTest) {
            debugPrint('[SocketService] Discarding stale/historical alert ($alertAgeMs ms old): ${event.id} (${event.symbol} ${event.level})');
            return;
          }

          final debounceKey = '${event.symbol}_${event.level}_${event.levelPrice.toStringAsFixed(2)}';
          final lastTrigger = _recentAlertTimestamps[debounceKey] ?? 0;
          final isRecentDuplicate = (now - lastTrigger) < 15000;

          debugPrint('[SocketService] 🚨 Price Alert Triggered: ${event.symbol} ${event.level} @ \$${event.currentPrice} (isDuplicate: $isRecentDuplicate)');

          // 1. Auto-remove triggered alert from active list
          final alertId = map['alertId']?.toString() ?? event.id;
          activeAlerts.removeWhere((a) => a.id == alertId || (a.symbol.toUpperCase() == event.symbol.toUpperCase() && (a.targetPrice - event.levelPrice).abs() < 0.01));
          _dispatchActiveAlertsUpdate(activeAlerts);

          // 2. Update level states
          if (map['alertStates'] != null && map['alertStates'] is Map) {
            final states = Map<String, dynamic>.from(map['alertStates'] as Map);
            states.forEach((k, v) {
              if (v is Map && v['status'] != null) {
                levelStates[k] = v['status'].toString();
              } else if (v != null) {
                levelStates[k] = v.toString();
              }
            });
            _dispatchLevelStatesUpdate(levelStates);
          }

          // 3. Update recent alerts list
          final existingIdx = recentAlerts.indexWhere(
            (a) => a.id == event.id || (a.level == event.level && a.symbol == event.symbol && (now - a.timestamp.millisecondsSinceEpoch).abs() < 25000),
          );

          if (existingIdx >= 0) {
            recentAlerts[existingIdx] = event;
          } else {
            recentAlerts.insert(0, event);
            if (recentAlerts.length > 6) {
              recentAlerts = recentAlerts.sublist(0, 6);
            }
          }
          _dispatchAlertsUpdate(recentAlerts);

          // 4. Trigger UI dialog, audio alarm & push notification (strictly once per touch event)
          if (!isRecentDuplicate) {
            _recentAlertTimestamps[debounceKey] = now;
            _recentAlertTimestamps[event.id] = now;
            NotificationService().recordRecentAlert(event.id);

            _dispatchAlertTriggered(event);

            try { AudioService().playAlertSound(); } catch (_) {}
            try { NotificationService().showAlertNotification(event); } catch (_) {}
          }
        } catch (e, stack) {
          debugPrint('[SocketService] handleIncomingAlert error: $e\n$stack');
        }
      }

      _socket?.on('alert:triggered', handleIncomingAlert);
      _socket?.on('alert_triggered', handleIncomingAlert);
      _socket?.on('custom_alert:triggered', handleIncomingAlert);

      _socket?.connect();
    } catch (e) {
      debugPrint('[SocketService] connectSocket exception: $e');
      _dispatchConnectionChange(false);
    }
  }

  /// Fetch all active alerts for current symbol
  Future<void> fetchActiveAlerts() async {
    try {
      final res = await http.get(Uri.parse('$_serverUrl/api/alerts/custom/list?symbol=$activeSymbol')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null && body['data'] is List) {
          activeAlerts = (body['data'] as List)
              .map((i) => PriceAlertModel.fromJson(Map<String, dynamic>.from(i as Map)))
              .toList();
          _dispatchActiveAlertsUpdate(activeAlerts);
        }
      }
    } catch (e) {
      debugPrint('[SocketService] fetchActiveAlerts error: $e');
    }
  }

  /// Create a new custom price alert
  Future<bool> createCustomAlert({
    required double targetPrice,
    String condition = 'ANY',
    String note = '',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_serverUrl/api/alerts/custom/create'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'symbol': activeSymbol,
          'targetPrice': targetPrice,
          'condition': condition,
          'note': note,
          'createdBy': 'APP',
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null) {
          final newAlert = PriceAlertModel.fromJson(Map<String, dynamic>.from(body['data']));
          activeAlerts.removeWhere((a) => a.id == newAlert.id);
          activeAlerts.insert(0, newAlert);
          _dispatchActiveAlertsUpdate(activeAlerts);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[SocketService] createCustomAlert error: $e');
    }
    return false;
  }

  /// Delete an active alert by ID
  Future<bool> deleteCustomAlertById(String alertId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_serverUrl/api/alerts/custom/$alertId?symbol=$activeSymbol'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        activeAlerts.removeWhere((a) => a.id == alertId);
        _dispatchActiveAlertsUpdate(activeAlerts);
        return true;
      }
    } catch (e) {
      debugPrint('[SocketService] deleteCustomAlertById error: $e');
    }
    return false;
  }

  /// Clear all active custom alerts for the active symbol
  Future<bool> clearAllCustomAlerts() async {
    try {
      final res = await http.post(
        Uri.parse('$_serverUrl/api/alerts/custom/clear'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'symbol': activeSymbol}),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        activeAlerts.clear();
        _dispatchActiveAlertsUpdate(activeAlerts);
        return true;
      }
    } catch (e) {
      debugPrint('[SocketService] clearAllCustomAlerts error: $e');
    }
    return false;
  }

  // Legacy single alert compatibility helper
  Future<bool> setCustomPriceAlert({required double targetPrice, required bool enabled}) async {
    if (!enabled) {
      return await clearAllCustomAlerts();
    }
    return await createCustomAlert(targetPrice: targetPrice);
  }

  Future<bool> deleteCustomPriceAlert() async {
    return await clearAllCustomAlerts();
  }

  Future<bool> updateRemoteConfig(Map<String, dynamic> data) async {
    try {
      final updatedMap = {
        'symbol': activeSymbol,
        'chartTimeframe': currentConfig.chartTimeframe,
        'chartRange': currentConfig.chartRange,
        'barSpacing': currentConfig.barSpacing,
        'customPriceAlertEnabled': currentConfig.customPriceAlertEnabled,
        'customPriceAlertTarget': currentConfig.customPriceAlertTarget,
        ...data,
      };
      currentConfig = PivotConfig.fromJson(updatedMap);
      _dispatchConfigUpdate(currentConfig);
    } catch (_) {}

    try {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('config:update', {
          'symbol': activeSymbol,
          ...data,
        });
      }
    } catch (_) {}

    try {
      final payload = {
        'symbol': activeSymbol,
        ...data,
      };
      final res = await http.put(
        Uri.parse('$_serverUrl/api/config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null) {
          currentConfig = PivotConfig.fromJson(Map<String, dynamic>.from(body['data']));
          _dispatchConfigUpdate(currentConfig);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[SocketService] updateRemoteConfig HTTP note: $e');
    }
    return _socket != null && _socket!.connected;
  }

  Future<Map<String, dynamic>> checkServerConnectivity() async {
    final sw = Stopwatch()..start();
    try {
      final res = await http.get(Uri.parse('$_serverUrl/api/health')).timeout(const Duration(seconds: 4));
      sw.stop();
      if (res.statusCode == 200) {
        return {
          'success': true,
          'message': 'Connected to $_serverUrl (${sw.elapsedMilliseconds}ms latency)',
        };
      }
      return {
        'success': false,
        'message': 'HTTP ${res.statusCode}: Server reachable',
      };
    } catch (e) {
      sw.stop();
      return {
        'success': false,
        'message': 'Connection failed: $e',
      };
    }
  }

  Future<void> triggerLocalTestAlert({String level = 'CUSTOM', double? price}) async {
    final targetPrice = price ?? (currentTick?.price ?? 3450.0);
    final testAlert = AlertEvent(
      id: 'local_test_${DateTime.now().millisecondsSinceEpoch}',
      symbol: activeSymbol,
      level: level,
      levelPrice: targetPrice,
      currentPrice: targetPrice,
      tolerance: 0.20,
      triggerReason: 'Manual Local Test Trigger',
      telegramStatus: 'SENT',
      timestamp: DateTime.now(),
      screenshotPath: '',
      isTest: true,
    );
    recentAlerts.insert(0, testAlert);
    if (recentAlerts.length > 6) {
      recentAlerts = recentAlerts.sublist(0, 6);
    }
    _dispatchAlertsUpdate(recentAlerts);
    _dispatchAlertTriggered(testAlert);
    try { AudioService().playAlertSound(); } catch (_) {}
    try { NotificationService().showAlertNotification(testAlert); } catch (_) {}
  }

  Future<bool> triggerRemoteTestAlert({String level = 'CUSTOM', double? price}) async {
    try {
      final targetPrice = price ?? (currentTick?.price ?? 3450.0);
      final res = await http.post(
        Uri.parse('$_serverUrl/api/alerts/test'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'symbol': activeSymbol,
          'level': level,
          'price': targetPrice,
        }),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[SocketService] triggerRemoteTestAlert error: $e');
      return false;
    }
  }

  void disconnectSocket() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _dispatchConnectionChange(false);
  }

  Future<void> fetchInitialData() async {
    try {
      // 1. Fetch Config
      final configRes = await http.get(Uri.parse('$_serverUrl/api/config?symbol=$activeSymbol')).timeout(const Duration(seconds: 5));
      if (configRes.statusCode == 200) {
        final body = json.decode(configRes.body);
        if (body['data'] != null) {
          final configMap = Map<String, dynamic>.from(body['data']);
          currentConfig = PivotConfig.fromJson(configMap);
          _dispatchConfigUpdate(currentConfig);
        }
      }

      // 2. Fetch Active Multi-Alerts
      await fetchActiveAlerts();

      // 3. Fetch Latest 6 Alerts
      final alertsRes = await http.get(Uri.parse('$_serverUrl/api/alerts?limit=6')).timeout(const Duration(seconds: 5));
      if (alertsRes.statusCode == 200) {
        final body = json.decode(alertsRes.body);
        if (body['data'] != null && body['data'] is List) {
          final list = (body['data'] as List).map((i) => AlertEvent.fromJson(Map<String, dynamic>.from(i))).toList();
          _dispatchAlertsUpdate(list.take(6).toList());
        }
      }

      // 4. Fetch Ticker
      final tickerRes = await http.get(Uri.parse('$_serverUrl/api/market/ticker')).timeout(const Duration(seconds: 5));
      if (tickerRes.statusCode == 200) {
        final body = json.decode(tickerRes.body);
        if (body['data'] != null) {
          final tick = MarketTick.fromJson(Map<String, dynamic>.from(body['data']));
          if (tick.price > 0) {
            _dispatchMarketTick(tick);
          }
        }
      }
    } catch (e) {
      debugPrint('[SocketService] fetchInitialData error: $e');
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
          'symbol': activeSymbol,
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
          _dispatchAlertsUpdate(recentAlerts);
          return event;
        }
      }
    } catch (e) {
      debugPrint('[SocketService] captureScreenshot error: $e');
    }
    return null;
  }

  Future<bool> deleteAlert(String id) async {
    try {
      final res = await http.delete(Uri.parse('$_serverUrl/api/alerts/$id')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        recentAlerts.removeWhere((a) => a.id == id);
        _dispatchAlertsUpdate(recentAlerts);
        return true;
      }
    } catch (e) {
      debugPrint('[SocketService] deleteAlert error: $e');
    }
    return false;
  }

  Future<List<SymbolModel>> searchSymbols(String query, {String assetType = 'ALL'}) async {
    try {
      final res = await http.get(
        Uri.parse('$_serverUrl/api/symbols/search?q=$query&assetType=$assetType'),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null && body['data'] is List) {
          return (body['data'] as List).map((i) => SymbolModel.fromJson(Map<String, dynamic>.from(i))).toList();
        }
      }
    } catch (e) {
      debugPrint('[SocketService] searchSymbols error: $e');
    }
    return [];
  }

  Future<bool> switchSymbol(String symbol) async {
    try {
      final res = await http.post(
        Uri.parse('$_serverUrl/api/symbols/active'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'symbol': symbol}),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null) {
          final data = Map<String, dynamic>.from(body['data']);
          activeSymbol = data['symbol']?.toString() ?? symbol;
          if (data['config'] != null) {
            activeSymbolConfig = SymbolModel.fromJson(Map<String, dynamic>.from(data['config']));
          }
          if (data['pivotState'] != null) {
            activePivotState = PivotStateModel.fromJson(Map<String, dynamic>.from(data['pivotState']));
          }
          if (data['market'] != null) {
            final tick = MarketTick.fromJson(Map<String, dynamic>.from(data['market']));
            _dispatchMarketTick(tick);
          }
          fetchActiveAlerts();
          _dispatchSymbolUpdate(activeSymbol, activeSymbolConfig, activePivotState);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[SocketService] switchSymbol error: $e');
    }
    return false;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    disconnectSocket();
  }
}
