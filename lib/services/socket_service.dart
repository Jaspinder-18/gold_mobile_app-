import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  SocketService._internal() {
    WidgetsBinding.instance.addObserver(this);
    // 25-second background & network heartbeat check
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _checkHealthAndReconnect();
    });
  }

  io.Socket? _socket;
  String _serverUrl = 'https://gold-server-dbbq.onrender.com';
  bool _isConnected = false;
  Timer? _heartbeatTimer;

  // Anti-duplicate alert debounce cache (prevents duplicate sound/notif triggers)
  final Map<String, int> _recentAlertTimestamps = {};

  MarketTick? currentTick;
  PivotConfig currentConfig = PivotConfig();
  SymbolModel? activeSymbolConfig;
  PivotStateModel? activePivotState;
  String activeSymbol = 'XAUUSD';
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
  Function(String, SymbolModel?, PivotStateModel?)? onSymbolUpdate;

  bool get isConnected => _isConnected;
  String get serverUrl => _serverUrl;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkHealthAndReconnect();
      fetchInitialData();
    }
  }

  void _checkHealthAndReconnect() {
    if (_socket == null || !_isConnected || !(_socket!.connected)) {
      connectSocket();
    }
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('server_url') ?? 'https://gold-server-dbbq.onrender.com';
    
    // Load local custom alert cache to prevent any switch flicker on startup
    final cachedEnabled = prefs.getBool('custom_price_alert_enabled_${activeSymbol.toUpperCase()}');
    final cachedTarget = prefs.getDouble('custom_price_alert_target_${activeSymbol.toUpperCase()}');
    if (cachedEnabled != null || cachedTarget != null) {
      currentConfig = currentConfig.copyWith(
        customPriceAlertEnabled: cachedEnabled ?? currentConfig.customPriceAlertEnabled,
        customPriceAlertTarget: cachedTarget ?? currentConfig.customPriceAlertTarget,
      );
      if (cachedEnabled == true && (cachedTarget ?? 0) > 0) {
        levelStates['CUSTOM'] = 'READY';
      }
    }

    await fetchInitialData();
    connectSocket();
  }

  Future<void> _persistCustomAlertState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('custom_price_alert_enabled_${activeSymbol.toUpperCase()}', currentConfig.customPriceAlertEnabled);
      await prefs.setDouble('custom_price_alert_target_${activeSymbol.toUpperCase()}', currentConfig.customPriceAlertTarget);
    } catch (e) {
      debugPrint('[SocketService] _persistCustomAlertState error: $e');
    }
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
      
      debugPrint('[SocketService] Connecting to $_serverUrl...');
      
      _socket = io.io(
        _serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(9999)
            .setReconnectionDelay(1000)
            .build(),
      );

      _socket?.onConnect((_) {
        debugPrint('[SocketService] ✓ Connected to Socket.IO Server');
        _isConnected = true;
        onConnectionChange?.call(true);
      });

      _socket?.onDisconnect((_) {
        debugPrint('[SocketService] ✕ Disconnected from Socket.IO Server');
        _isConnected = false;
        onConnectionChange?.call(false);
      });

      _socket?.onConnectError((err) {
        debugPrint('[SocketService] Connection Error: $err');
        _isConnected = false;
        onConnectionChange?.call(false);
      });

      _socket?.onError((err) {
        debugPrint('[SocketService] Socket Error: $err');
      });

      void handleTick(dynamic data) {
        if (data != null) {
          try {
            final map = Map<String, dynamic>.from(data as Map);
            currentTick = MarketTick.fromJson(map);
            onMarketTick?.call(currentTick!);
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
              currentTick = MarketTick.fromJson(Map<String, dynamic>.from(map['market'] as Map));
              onMarketTick?.call(currentTick!);
            } else if (map['price'] != null) {
              currentTick = MarketTick.fromJson(map);
              onMarketTick?.call(currentTick!);
            }
            if (map['config'] != null) {
              currentConfig = PivotConfig.fromJson(Map<String, dynamic>.from(map['config'] as Map));
              onConfigUpdate?.call(currentConfig);
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
              onLevelStatesUpdate?.call(levelStates);
            }
            onSymbolUpdate?.call(activeSymbol, activeSymbolConfig, activePivotState);
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
              currentTick = MarketTick.fromJson(Map<String, dynamic>.from(map['market'] as Map));
              onMarketTick?.call(currentTick!);
            }
            onSymbolUpdate?.call(activeSymbol, activeSymbolConfig, activePivotState);
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
            if (map['customPriceAlertStatus'] != null) {
              levelStates['CUSTOM'] = map['customPriceAlertStatus'].toString() == 'ACTIVE'
                  ? 'READY'
                  : map['customPriceAlertStatus'].toString();
            }
            onConfigUpdate?.call(currentConfig);
            _persistCustomAlertState();
          } catch (e) {
            debugPrint('[SocketService] config_updated error: $e');
          }
        }
      }
      _socket?.on('config_updated', handleConfig);
      _socket?.on('config:update', handleConfig);

      _socket?.on('custom_alert:updated', (data) {
        if (data != null && data is Map) {
          try {
            final map = Map<String, dynamic>.from(data);
            final sym = map['symbol']?.toString();
            if (sym != null && sym.toUpperCase() != activeSymbol.toUpperCase()) return;
            final isEn = map['customPriceAlertEnabled'] ?? map['customAlert']?['enabled'] ?? false;
            final tPrice = (map['customPriceAlertTarget'] ?? map['customAlert']?['targetPrice'] as num?)?.toDouble() ?? 0.0;
            final st = map['customPriceAlertStatus']?.toString() ??
                map['customAlert']?['status']?.toString() ??
                (isEn == true && tPrice > 0 ? 'ACTIVE' : 'INACTIVE');

            currentConfig = currentConfig.copyWith(
              customPriceAlertEnabled: isEn == true,
              customPriceAlertTarget: tPrice,
              customPriceAlertStatus: st,
            );
            levelStates['CUSTOM'] = st == 'ACTIVE' ? 'READY' : st;
            onConfigUpdate?.call(currentConfig);
            onLevelStatesUpdate?.call(levelStates);
            _persistCustomAlertState();
          } catch (e) {
            debugPrint('[SocketService] custom_alert:updated error: $e');
          }
        }
      });

      _socket?.on('custom_alert:deleted', (data) {
        currentConfig = currentConfig.copyWith(
          customPriceAlertEnabled: false,
          customPriceAlertTarget: 0.0,
          customPriceAlertStatus: 'INACTIVE',
        );
        levelStates['CUSTOM'] = 'INACTIVE';
        onConfigUpdate?.call(currentConfig);
        onLevelStatesUpdate?.call(levelStates);
        _persistCustomAlertState();
      });

      _socket?.on('custom_alert:triggered', (data) {
        currentConfig = currentConfig.copyWith(
          customPriceAlertEnabled: false,
          customPriceAlertStatus: 'TRIGGERED',
        );
        levelStates['CUSTOM'] = 'TRIGGERED';
        onConfigUpdate?.call(currentConfig);
        onLevelStatesUpdate?.call(levelStates);
        _persistCustomAlertState();
      });

      void handleLevelStates(dynamic data) {
        if (data != null) {
          try {
            final Map<String, dynamic> states = Map<String, dynamic>.from(data as Map);
            states.forEach((k, v) {
              if (v is Map && v['status'] != null) {
                levelStates[k] = v['status'].toString();
              } else if (v != null) {
                levelStates[k] = v.toString();
              }
            });
            onLevelStatesUpdate?.call(levelStates);
          } catch (e) {
            debugPrint('[SocketService] handleLevelStates error: $e');
          }
        }
      }
      _socket?.on('alert:states', handleLevelStates);
      _socket?.on('alert_states', handleLevelStates);

      _socket?.on('pivotUpdated', (data) {
        if (data != null) {
          try {
            final map = Map<String, dynamic>.from(data as Map);
            final updatedSym = map['symbol']?.toString();
            if (updatedSym != null && updatedSym.toUpperCase() != activeSymbol.toUpperCase()) {
              return;
            }
            activePivotState = PivotStateModel.fromJson(map);
            currentConfig = PivotConfig(
              r3: activePivotState!.r3,
              r2: activePivotState!.r2,
              s2: activePivotState!.s2,
              s3: activePivotState!.s3,
              tolerance: currentConfig.tolerance,
              retriggerDistance: currentConfig.retriggerDistance,
              chartTimeframe: currentConfig.chartTimeframe,
              chartRange: currentConfig.chartRange,
              barSpacing: currentConfig.barSpacing,
              telegramAlertsEnabled: currentConfig.telegramAlertsEnabled,
              autoCalculatePivot: currentConfig.autoCalculatePivot,
              autoCalcIntervalMinutes: currentConfig.autoCalcIntervalMinutes,
              customPriceAlertEnabled: currentConfig.customPriceAlertEnabled,
              customPriceAlertTarget: currentConfig.customPriceAlertTarget,
            );
            levelStates['R3'] = 'READY';
            levelStates['R2'] = 'READY';
            levelStates['S2'] = 'READY';
            levelStates['S3'] = 'READY';

            onConfigUpdate?.call(currentConfig);
            onLevelStatesUpdate?.call(levelStates);
            onSymbolUpdate?.call(activeSymbol, activeSymbolConfig, activePivotState);
          } catch (e) {
            debugPrint('[SocketService] pivotUpdated error: $e');
          }
        }
      });

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
          final debounceKey = '${event.symbol}_${event.level}';
          final lastTrigger = _recentAlertTimestamps[debounceKey] ?? 0;
          final isRecentDuplicate = (now - lastTrigger) < 6000; // 6-second lock for audio/dialog re-trigger

          debugPrint('[SocketService] 🚨 Level Alert Received: ${event.symbol} ${event.level} @ \$${event.currentPrice} (isDuplicate: $isRecentDuplicate, hasScreenshot: ${event.screenshotPath.isNotEmpty})');

          // 1. Update level state indicators if available
          if (map['alertStates'] != null && map['alertStates'] is Map) {
            final states = Map<String, dynamic>.from(map['alertStates'] as Map);
            states.forEach((k, v) {
              if (v is Map && v['status'] != null) {
                levelStates[k] = v['status'].toString();
              } else if (v != null) {
                levelStates[k] = v.toString();
              }
            });
          } else {
            levelStates[event.level] = 'TRIGGERED';
          }
          onLevelStatesUpdate?.call(levelStates);

          // 2. Update recent alerts list in-place or prepend
          final existingIdx = recentAlerts.indexWhere(
            (a) => a.id == event.id || (a.level == event.level && a.symbol == event.symbol && (now - a.timestamp.millisecondsSinceEpoch).abs() < 25000),
          );

          if (existingIdx >= 0) {
            // Update existing with finalized screenshot
            recentAlerts[existingIdx] = event;
          } else {
            recentAlerts.insert(0, event);
            if (recentAlerts.length > 6) {
              recentAlerts = recentAlerts.sublist(0, 6);
            }
          }
          onAlertsUpdate?.call(recentAlerts);

          // 3. If this is a fresh new touch trigger (not a duplicate fast-broadcast follow up or screenshot completion)
          if (!isRecentDuplicate) {
            _recentAlertTimestamps[debounceKey] = now;

            // Trigger in-app UI dialog
            onAlertTriggered?.call(event);

            // Play Loud Alarm Clock / Ringtone Sound
            await AudioService().playAlertSound();

            // Dispatch System Notification with Direct Tap Navigation
            await NotificationService().showAlertNotification(event);
          } else if (event.screenshotPath.isNotEmpty) {
            debugPrint('[SocketService] Finalized screenshot captured for ${event.level}: ${event.screenshotPath}');
          }
        } catch (e, stack) {
          debugPrint('[SocketService] handleIncomingAlert error: $e\n$stack');
        }
      }

      // Register primary alert event
      _socket?.on('alert:triggered', handleIncomingAlert);
      _socket?.on('alert_triggered', handleIncomingAlert);

      // Now initiate connection
      _socket?.connect();
    } catch (e) {
      debugPrint('[SocketService] connectSocket exception: $e');
      _isConnected = false;
      onConnectionChange?.call(false);
    }
  }

  /// Manually trigger a full end-to-end alert test on this device (Sound + Notification + Dialog)
  Future<void> triggerLocalTestAlert({String level = 'R2', double price = 4580.75}) async {
    final event = AlertEvent(
      id: 'local_test_${DateTime.now().millisecondsSinceEpoch}',
      symbol: activeSymbol,
      displayName: activeSymbolConfig?.displayName ?? '$activeSymbol Spot',
      level: level,
      levelPrice: price,
      currentPrice: price,
      tolerance: currentConfig.tolerance,
      screenshotPath: '',
      triggerReason: 'Local Test Alert for level $level @ \$${price.toStringAsFixed(2)}',
      telegramStatus: 'TEST',
      timestamp: DateTime.now(),
      isTest: true,
    );

    levelStates[level] = 'TRIGGERED';
    onLevelStatesUpdate?.call(levelStates);

    recentAlerts.removeWhere((a) => a.id == event.id);
    recentAlerts.insert(0, event);
    if (recentAlerts.length > 6) {
      recentAlerts = recentAlerts.sublist(0, 6);
    }
    onAlertsUpdate?.call(recentAlerts);

    onAlertTriggered?.call(event);
    await AudioService().playAlertSound();
    await NotificationService().showAlertNotification(event);
  }

  /// Trigger a live simulated alert test from backend server (broadcasts to Web & Mobile via WebSocket)
  Future<bool> triggerRemoteTestAlert({String level = 'R2', double? price}) async {
    try {
      final payload = {
        'level': level,
        if (price != null) 'price': price,
      };
      final res = await http.post(
        Uri.parse('$_serverUrl/api/test/trigger-alert'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[SocketService] triggerRemoteTestAlert error: $e');
      return false;
    }
  }

  /// Ping server to test HTTP & WebSocket connectivity with latency measurement
  Future<Map<String, dynamic>> checkServerConnectivity() async {
    final stopwatch = Stopwatch()..start();
    try {
      final res = await http.get(Uri.parse('$_serverUrl/api/market/ticker')).timeout(const Duration(seconds: 6));
      stopwatch.stop();
      if (res.statusCode == 200) {
        return {
          'success': true,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'message': 'Connected (${stopwatch.elapsedMilliseconds}ms)',
          'isSocketConnected': _isConnected,
        };
      } else {
        return {
          'success': false,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'message': 'Server responded with status ${res.statusCode}',
          'isSocketConnected': _isConnected,
        };
      }
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'message': 'Connection failed: ${e.toString()}',
        'isSocketConnected': _isConnected,
      };
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
      debugPrint('[SocketService] autoCalculatePivots error: $e');
    }
    return false;
  }

  Future<bool> updateRemoteConfig(Map<String, dynamic> updates) async {
    try {
      final payload = {
        'symbol': activeSymbol,
        ...updates,
      };
      final res = await http.put(
        Uri.parse('$_serverUrl/api/config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
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
      debugPrint('[SocketService] updateRemoteConfig error: $e');
    }
    return false;
  }

  Future<bool> setCustomPriceAlert({
    required double targetPrice,
    required bool enabled,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_serverUrl/api/alerts/custom'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'symbol': activeSymbol,
          'targetPrice': targetPrice,
          'enabled': enabled,
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['data'] != null) {
          final data = Map<String, dynamic>.from(body['data']);
          currentConfig = currentConfig.copyWith(
            customPriceAlertTarget: (data['targetPrice'] as num?)?.toDouble() ?? targetPrice,
            customPriceAlertEnabled: data['enabled'] ?? enabled,
            customPriceAlertStatus: data['status']?.toString() ?? (enabled && targetPrice > 0 ? 'ACTIVE' : 'INACTIVE'),
          );
          levelStates['CUSTOM'] = currentConfig.customPriceAlertStatus == 'ACTIVE' ? 'READY' : currentConfig.customPriceAlertStatus;
          onConfigUpdate?.call(currentConfig);
          onLevelStatesUpdate?.call(levelStates);
          _persistCustomAlertState();
          return true;
        }
      }
    } catch (e) {
      debugPrint('[SocketService] setCustomPriceAlert error: $e');
    }

    final ok = await updateRemoteConfig({
      'customPriceAlertTarget': targetPrice,
      'customPriceAlertEnabled': enabled,
    });
    if (ok) _persistCustomAlertState();
    return ok;
  }

  Future<bool> deleteCustomPriceAlert() async {
    try {
      final res = await http.delete(
        Uri.parse('$_serverUrl/api/alerts/custom/$activeSymbol'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        currentConfig = currentConfig.copyWith(
          customPriceAlertTarget: 0.0,
          customPriceAlertEnabled: false,
          customPriceAlertStatus: 'INACTIVE',
        );
        levelStates['CUSTOM'] = 'INACTIVE';
        onConfigUpdate?.call(currentConfig);
        onLevelStatesUpdate?.call(levelStates);
        _persistCustomAlertState();
        return true;
      }
    } catch (e) {
      debugPrint('[SocketService] deleteCustomPriceAlert error: $e');
    }

    final ok = await updateRemoteConfig({
      'customPriceAlertTarget': 0.0,
      'customPriceAlertEnabled': false,
    });
    if (ok) _persistCustomAlertState();
    return ok;
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
      // 1. Fetch Config directly from Online Database (Single Source of Truth)
      final configRes = await http.get(Uri.parse('$_serverUrl/api/config?symbol=$activeSymbol')).timeout(const Duration(seconds: 5));
      if (configRes.statusCode == 200) {
        final body = json.decode(configRes.body);
        if (body['data'] != null) {
          final configMap = Map<String, dynamic>.from(body['data']);
          currentConfig = PivotConfig.fromJson(configMap);
          if (configMap['customPriceAlertStatus'] != null) {
            levelStates['CUSTOM'] = configMap['customPriceAlertStatus'].toString() == 'ACTIVE'
                ? 'READY'
                : configMap['customPriceAlertStatus'].toString();
          }
          onConfigUpdate?.call(currentConfig);
          onLevelStatesUpdate?.call(levelStates);
          _persistCustomAlertState();
        }
      }

      // 1b. Specifically fetch custom alert status to ensure 100% online database parity
      try {
        final customRes = await http.get(Uri.parse('$_serverUrl/api/alerts/custom?symbol=$activeSymbol')).timeout(const Duration(seconds: 4));
        if (customRes.statusCode == 200) {
          final body = json.decode(customRes.body);
          if (body['data'] != null) {
            final data = Map<String, dynamic>.from(body['data']);
            final bool isEn = data['enabled'] == true;
            final double tPrice = (data['targetPrice'] as num?)?.toDouble() ?? 0.0;
            final String st = data['status']?.toString() ?? (isEn && tPrice > 0 ? 'ACTIVE' : 'INACTIVE');
            currentConfig = currentConfig.copyWith(
              customPriceAlertEnabled: isEn,
              customPriceAlertTarget: tPrice,
              customPriceAlertStatus: st,
            );
            levelStates['CUSTOM'] = st == 'ACTIVE' ? 'READY' : st;
            onConfigUpdate?.call(currentConfig);
            onLevelStatesUpdate?.call(levelStates);
            _persistCustomAlertState();
          }
        }
      } catch (e) {
        debugPrint('[SocketService] fetch custom alert error: $e');
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
          onAlertsUpdate?.call(recentAlerts);
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
        onAlertsUpdate?.call(recentAlerts);
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
            currentTick = MarketTick.fromJson(Map<String, dynamic>.from(data['market']));
            onMarketTick?.call(currentTick!);
          }
          onSymbolUpdate?.call(activeSymbol, activeSymbolConfig, activePivotState);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[SocketService] switchSymbol error: $e');
    }
    return false;
  }
}
