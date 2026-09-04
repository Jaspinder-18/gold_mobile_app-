import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/market_data.dart';
import '../services/socket_service.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import 'screenshot_viewer_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final SocketService _socketService = SocketService();
  int _currentTabIndex = 0;
  bool _isCapturing = false;

  MarketTick? _tick;
  PivotConfig _config = PivotConfig();
  List<AlertEvent> _alerts = [];
  bool _isConnected = false;
  double _previousPrice = 0.0;
  String _tickDirection = 'UP';

  final List<String> _timeframes = ['1M', '3M', '5M', '15M', '30M', '1H', '4H', '1D'];

  @override
  void initState() {
    super.initState();
    _initListeners();
    // Ensure notifications permission is requested when UI is visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().requestPermissions();
    });
  }

  bool _isAlertDialogOpen = false;
  final TextEditingController _customTargetPriceController = TextEditingController();
  bool _isSavingCustomAlert = false;

  @override
  void dispose() {
    _customTargetPriceController.dispose();
    super.dispose();
  }

  void _initListeners() {
    _tick = _socketService.currentTick;
    _config = _socketService.currentConfig;
    _alerts = _socketService.recentAlerts;
    _isConnected = _socketService.isConnected;
    if (_config.customPriceAlertTarget > 0) {
      _customTargetPriceController.text = _config.customPriceAlertTarget.toStringAsFixed(2);
    }
    if (_tick != null) {
      _previousPrice = _tick!.price;
      _tickDirection = _tick!.change >= 0 ? 'UP' : 'DOWN';
    }

    _socketService.onMarketTick = (tick) {
      if (mounted) {
        setState(() {
          if (_previousPrice > 0) {
            if (tick.price > _previousPrice) {
              _tickDirection = 'UP';
            } else if (tick.price < _previousPrice) {
              _tickDirection = 'DOWN';
            }
          } else {
            _tickDirection = tick.change >= 0 ? 'UP' : 'DOWN';
          }
          _previousPrice = tick.price;
          _tick = tick;
        });
      }
    };

    _socketService.onConfigUpdate = (config) {
      if (mounted) {
        setState(() {
          _config = config;
          if (config.customPriceAlertTarget > 0) {
            _customTargetPriceController.text = config.customPriceAlertTarget.toStringAsFixed(2);
          } else if (!config.customPriceAlertEnabled && config.customPriceAlertTarget == 0) {
            _customTargetPriceController.clear();
          }
        });
      }
    };

    _socketService.onAlertsUpdate = (alerts) {
      if (mounted) setState(() => _alerts = alerts);
    };

    _socketService.onLevelStatesUpdate = (states) {
      if (mounted) setState(() {});
    };

    _socketService.onConnectionChange = (connected) {
      if (mounted) setState(() => _isConnected = connected);
    };

    _socketService.onSymbolUpdate = (symbol, symConfig, pivotState) {
      if (mounted) setState(() {});
    };

    _socketService.onAlertTriggered = (event) {
      if (mounted) {
        _showIncomingAlertDialog(event);
      }
    };

    NotificationService().onNotificationTap = (payload) {
      AudioService().stop();
      if (!mounted) return;
      if (_alerts.isNotEmpty) {
        final targetAlert = _alerts.firstWhere(
          (a) => a.screenshotPath == payload || a.id == payload,
          orElse: () => _alerts.first,
        );
        _openScreenshotViewer(targetAlert);
      }
    };
  }

  void _showSymbolSearchBottomSheet() {
    String searchQ = '';
    String assetTab = 'ALL';
    List<SymbolModel> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1120),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void runSearch() async {
              setModalState(() => isSearching = true);
              final results = await _socketService.searchSymbols(searchQ, assetType: assetTab);
              if (ctx.mounted) {
                setModalState(() {
                  searchResults = results;
                  isSearching = false;
                });
              }
            }

            if (searchResults.isEmpty && !isSearching && searchQ.isEmpty) {
              runSearch();
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Search Bar
                  TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search symbol (Gold, BTC, Nifty, EURUSD)...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 18),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) {
                      searchQ = val;
                      runSearch();
                    },
                  ),
                  const SizedBox(height: 10),
                  // Category Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['ALL', 'COMMODITY', 'CRYPTO', 'FOREX', 'INDEX', 'STOCK'].map((tab) {
                        final isSel = assetTab == tab;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(tab, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.black : Colors.white70)),
                            selected: isSel,
                            selectedColor: const Color(0xFFF59E0B),
                            backgroundColor: const Color(0xFF1E293B),
                            onSelected: (sel) {
                              if (sel) {
                                setModalState(() => assetTab = tab);
                                runSearch();
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Results List
                  Expanded(
                    child: isSearching
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                        : searchResults.isEmpty
                            ? const Center(child: Text('No matching assets found', style: TextStyle(color: Colors.grey, fontSize: 12)))
                            : ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (ctx, idx) {
                                  final sym = searchResults[idx];
                                  final isActive = _socketService.activeSymbol == sym.symbol;
                                  return Card(
                                    color: isActive ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFF131D31),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: isActive ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                                    ),
                                    child: ListTile(
                                      title: Row(
                                        children: [
                                          Text(sym.symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(4)),
                                            child: Text(sym.assetType, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                      subtitle: Text('${sym.displayName} • ${sym.exchange}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      trailing: isActive
                                          ? const Icon(Icons.check_circle, color: Color(0xFFF59E0B), size: 20)
                                          : const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14),
                                      onTap: () async {
                                        Navigator.pop(bctx);
                                        await _socketService.switchSymbol(sym.symbol);
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showIncomingAlertDialog(AlertEvent event) {
    if (!mounted) return;

    // Safely dismiss any already open alert dialog before displaying the new one
    if (_isAlertDialogOpen) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      _isAlertDialogOpen = false;
    }

    _isAlertDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFEF4444), width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.alarm, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🚨 ${event.level} TOUCHED!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${event.displayName.isNotEmpty ? event.displayName : (event.symbol.isNotEmpty ? event.symbol : "Target")} touched ${event.level} at \$${event.currentPrice.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (event.screenshotPath.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: _formatImageUrl(event.screenshotPath),
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => Container(color: Colors.black),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('DISMISS', style: TextStyle(color: Colors.grey, fontSize: 12)),
            onPressed: () {
              _isAlertDialogOpen = false;
              AudioService().stop();
              Navigator.pop(ctx);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.fullscreen, color: Colors.black, size: 16),
            label: const Text('VIEW CHART', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            onPressed: () {
              _isAlertDialogOpen = false;
              AudioService().stop();
              Navigator.pop(ctx);
              _openScreenshotViewer(event);
            },
          ),
        ],
      ),
    ).then((_) {
      _isAlertDialogOpen = false;
    });
  }

  String _formatImageUrl(String path) {
    if (path.startsWith('http')) return path;
    return '${_socketService.serverUrl}$path';
  }

  void _openScreenshotViewer(AlertEvent event) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScreenshotViewerScreen(event: event)),
    );
  }

  Future<void> _handleManualCapture() async {
    setState(() => _isCapturing = true);
    final event = await _socketService.captureScreenshot(
      timeframe: _config.chartTimeframe,
      range: _config.chartRange,
      barSpacing: _config.barSpacing,
    );
    if (mounted) {
      setState(() => _isCapturing = false);
      if (event != null) {
        _openScreenshotViewer(event);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final currentPrice = _tick?.price ?? 4481.17;
    final latestAlertWithImage = _alerts.isNotEmpty ? _alerts.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1626),
        elevation: 0,
        titleSpacing: 12,
        title: InkWell(
          onTap: _showSymbolSearchBottomSheet,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 16),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          _socketService.activeSymbol,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, color: Color(0xFFF59E0B), size: 16),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isConnected ? 'LIVE FEED ACTIVE' : 'CONNECTING...',
                          style: TextStyle(
                            color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (AudioService().isPlaying)
            IconButton(
              icon: const Icon(Icons.volume_off, color: Colors.redAccent, size: 22),
              tooltip: 'Silence Alarm',
              onPressed: () async {
                await AudioService().stop();
                if (mounted) setState(() {});
              },
            ),
          IconButton(
            icon: const Icon(Icons.tune, color: Color(0xFFF59E0B), size: 20),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildMonitorTab(currentPrice, latestAlertWithImage),
          _buildScreenshotsTab(),
          _buildAlertsTab(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1626),
          border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) => setState(() => _currentTabIndex = index),
          backgroundColor: const Color(0xFF0E1626),
          selectedItemColor: const Color(0xFFF59E0B),
          unselectedItemColor: Colors.white54,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined, size: 20), activeIcon: Icon(Icons.dashboard, size: 20), label: 'Monitor'),
            BottomNavigationBarItem(icon: Icon(Icons.photo_library_outlined, size: 20), activeIcon: Icon(Icons.photo_library, size: 20), label: 'Captures'),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_none, size: 20), activeIcon: Icon(Icons.notifications, size: 20), label: 'Alerts'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined, size: 20), activeIcon: Icon(Icons.settings, size: 20), label: 'Config'),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitorTab(double currentPrice, AlertEvent? latestAlert) {
    return RefreshIndicator(
      color: const Color(0xFFF59E0B),
      backgroundColor: const Color(0xFF0F172A),
      onRefresh: () => _socketService.fetchInitialData(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          // 1. LIVE SPOT PRICE & TRADINGVIEW CONTROLS (MATCHES WEB APP)
          _buildWebStyleSpotPriceCard(currentPrice),

          const SizedBox(height: 12),

          // 2. CUSTOM TARGET PRICE ALERT (ON / OFF TOGGLE & DYNAMIC PRICE)
          _buildCustomTargetPriceAlertCard(currentPrice),

          const SizedBox(height: 12),

          // 3. COMPACT CHART SCREENSHOT CARD
          _buildCompactScreenshotCard(latestAlert),
        ],
      ),
    );
  }

  Future<void> _handleSaveCustomTargetAlert({bool? newEnabledState}) async {
    setState(() => _isSavingCustomAlert = true);
    final targetVal = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? _config.customPriceAlertTarget;
    final enabled = newEnabledState ?? true;

    final ok = await _socketService.setCustomPriceAlert(
      targetPrice: targetVal,
      enabled: enabled,
    );

    if (mounted) {
      setState(() => _isSavingCustomAlert = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            ok
                ? (enabled
                    ? '🎯 Custom Price Alert ARMED at \$${targetVal.toStringAsFixed(2)} & synced to all devices!'
                    : '⏸ Custom Price Alert PAUSED.')
                : 'Failed to update custom price alert in online DB.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleDeleteCustomTargetAlert() async {
    setState(() => _isSavingCustomAlert = true);
    final ok = await _socketService.deleteCustomPriceAlert();
    if (mounted) {
      _customTargetPriceController.clear();
      setState(() => _isSavingCustomAlert = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            ok ? '🗑️ Custom Price Alert DELETED from Online DB.' : 'Failed to delete custom price alert.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildCustomTargetPriceAlertCard(double currentPrice) {
    final isEnabled = _config.customPriceAlertEnabled;
    final targetPrice = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? _config.customPriceAlertTarget;
    final distance = (currentPrice - targetPrice).abs();
    final customState = _socketService.levelStates['CUSTOM'] ?? 'READY';
    final isTouched = customState == 'TRIGGERED' || (isEnabled && targetPrice > 0 && distance <= _config.tolerance);
    final isAbove = targetPrice > currentPrice;
    final audio = AudioService();

    // Proximity calculation (0.0 to 1.0)
    double proximity = 0.0;
    if (targetPrice > 0) {
      final range = (currentPrice * 0.02).clamp(1.0, 100.0);
      proximity = (1.0 - (distance / range)).clamp(0.05, 1.0);
    }

    Color borderColor;
    Color bgColor;
    if (isTouched) {
      borderColor = const Color(0xFFEF4444);
      bgColor = const Color(0xFFEF4444).withValues(alpha: 0.16);
    } else if (isEnabled) {
      borderColor = const Color(0xFFF59E0B);
      bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.09);
    } else {
      borderColor = const Color(0xFF1E293B);
      bgColor = const Color(0xFF0F172A);
    }

    // Dynamic increment values based on asset type
    final assetType = _socketService.activeSymbolConfig?.assetType ?? 'COMMODITY';
    List<double> increments;
    if (assetType == 'CRYPTO') {
      increments = [50.0, 100.0, 500.0];
    } else if (assetType == 'FOREX') {
      increments = [0.0010, 0.0050, 0.0100];
    } else if (assetType == 'INDEX') {
      increments = [5.0, 25.0, 50.0];
    } else {
      increments = [1.0, 5.0, 10.0];
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isEnabled ? 1.5 : 1),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: isTouched
                      ? const Color(0xFFEF4444).withValues(alpha: 0.22)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title & Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: isEnabled ? const Color(0xFFF59E0B).withValues(alpha: 0.25) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.my_location, color: isEnabled ? const Color(0xFFF59E0B) : Colors.grey, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CUSTOM TARGET PRICE ALERT',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                      ),
                      Text(
                        isTouched
                            ? '🎯 TARGET HIT: Alert triggered (Switch OFF)'
                            : (isEnabled ? 'Alarm + Push + Screenshot armed on price hit' : 'Alert currently paused / off'),
                        style: TextStyle(
                          color: isTouched
                              ? const Color(0xFFEF4444)
                              : (isEnabled ? const Color(0xFFFBBF24) : Colors.white38),
                          fontSize: 9,
                          fontWeight: isTouched ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: isEnabled,
                  activeColor: const Color(0xFFF59E0B),
                  activeTrackColor: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                  inactiveThumbColor: Colors.grey[600],
                  inactiveTrackColor: const Color(0xFF1E293B),
                  onChanged: (val) {
                    _handleSaveCustomTargetAlert(newEnabledState: val);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Price Input and Quick Current Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _customTargetPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 15),
                    hintText: '4410.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF070A12),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.flash_on, size: 12, color: Colors.black),
                  label: const Text('CURRENT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    _customTargetPriceController.text = currentPrice.toStringAsFixed(2);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Quick Increment/Decrement Buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...increments.map((inc) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _buildQuickAdjPill('+${inc >= 1 ? inc.toStringAsFixed(inc.truncateToDouble() == inc ? 0 : 2) : inc.toStringAsFixed(4)}', inc),
                )),
                const SizedBox(width: 4),
                ...increments.map((inc) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _buildQuickAdjPill('-${inc >= 1 ? inc.toStringAsFixed(inc.truncateToDouble() == inc ? 0 : 2) : inc.toStringAsFixed(4)}', -inc),
                )),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Mini Alarm Sound & Loop Preview Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.volume_up, color: Color(0xFFF59E0B), size: 13),
                    const SizedBox(width: 6),
                    Text(
                      '${audio.currentSound.title.split('(')[0].trim()} • ${audio.loopMode.label.split('(')[0].trim()}',
                      style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () async {
                    if (audio.isPlaying) {
                      await audio.stop();
                    } else {
                      await audio.testSound(audio.currentSound);
                    }
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: audio.isPlaying ? const Color(0xFFEF4444).withValues(alpha: 0.2) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: audio.isPlaying ? const Color(0xFFEF4444) : Colors.white24),
                    ),
                    child: Text(
                      audio.isPlaying ? '■ STOP' : '▶ TEST SOUND',
                      style: TextStyle(
                        color: audio.isPlaying ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Live Distance and Save / Arm Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        targetPrice > 0
                            ? (isAbove ? '↗ Target Above (+\$${distance.toStringAsFixed(2)})' : '↘ Target Below (-\$${distance.toStringAsFixed(2)})')
                            : 'Enter target price above',
                        style: TextStyle(
                          color: isTouched
                              ? const Color(0xFFEF4444)
                              : (isEnabled ? const Color(0xFFFBBF24) : Colors.white54),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (isEnabled && targetPrice > 0) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: proximity,
                            minHeight: 3,
                            backgroundColor: const Color(0xFF1E293B),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isTouched ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _isSavingCustomAlert ? null : () => _handleSaveCustomTargetAlert(newEnabledState: true),
                  child: _isSavingCustomAlert
                      ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(
                          isEnabled ? 'UPDATE & ARM' : 'ARM ALERT',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 9.5),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAdjPill(String label, double delta) {
    return InkWell(
      onTap: () {
        final current = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? (_tick?.price ?? 4400.0);
        final next = (current + delta).clamp(0.0, 999999.0);
        _customTargetPriceController.text = next.toStringAsFixed(2);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: delta > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildWebStyleSpotPriceCard(double price) {
    final change = _tick?.change ?? -40.23;
    final changePercent = _tick?.changePercent ?? -0.89;
    final isDayPos = change >= 0;
    final isTickUp = _tickDirection == 'UP';
    final bid = _tick?.bid ?? (price - 0.25);
    final ask = _tick?.ask ?? (price + 0.25);
    final spread = (ask - bid).abs();
    final timeStr = DateFormat('HH:mm:ss').format(DateTime.now());

    final tickColor = isTickUp ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final dayColor = isDayPos ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTickUp ? const Color(0xFF059669).withValues(alpha: 0.5) : const Color(0xFFDC2626).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isTickUp ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFEF4444).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    _socketService.activeSymbolConfig?.displayName ?? _tick?.displayName ?? _tick?.symbol ?? _socketService.activeSymbol,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${_socketService.activeSymbol})',
                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isTickUp ? const Color(0xFF064E3B).withValues(alpha: 0.6) : const Color(0xFF450A0A).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tickColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isTickUp ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: tickColor, size: 16),
                    Text(
                      isTickUp ? 'TICK UP' : 'TICK DOWN',
                      style: TextStyle(color: tickColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Price & Badges Row (Prevents overflow & dynamically colors UP/DOWN)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '\$${NumberFormat('#,##0.00').format(price)}',
                    style: TextStyle(
                      color: tickColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      fontFamily: 'monospace',
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isTickUp ? const Color(0xFF064E3B).withValues(alpha: 0.7) : const Color(0xFF450A0A).withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: tickColor.withValues(alpha: 0.7)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isTickUp ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: tickColor, size: 14),
                        Text(
                          isTickUp ? 'UP' : 'DOWN',
                          style: TextStyle(color: tickColor, fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isDayPos ? const Color(0xFF064E3B).withValues(alpha: 0.7) : const Color(0xFF450A0A).withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: dayColor.withValues(alpha: 0.7)),
                    ),
                    child: Text(
                      '${isDayPos ? '↗ +' : '↘ '}${change.toStringAsFixed(2)} (${changePercent.toStringAsFixed(2)}%)',
                      style: TextStyle(
                        color: dayColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Bid / Ask / Spread Row
          Row(
            children: [
              Text('Bid: ', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('\$${bid.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Container(width: 1, height: 10, color: Colors.white24),
              const SizedBox(width: 10),
              Text('Ask: ', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('\$${ask.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Container(width: 1, height: 10, color: Colors.white24),
              const SizedBox(width: 10),
              Text('Spread: ', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('\$${spread.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ],
          ),

          const SizedBox(height: 12),

          // Capture Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isCapturing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.camera_alt, color: Colors.black, size: 16),
              label: Text(
                _isCapturing ? 'CAPTURING...' : 'CAPTURE NOW',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 3,
              ),
              onPressed: _isCapturing ? null : _handleManualCapture,
            ),
          ),

          const SizedBox(height: 12),

          // 3 Stat Tiles
          Row(
            children: [
              // Tile 1: Feed Status
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070A12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Feed Status', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          const Text('LIVE STREAM', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 8, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Tile 2: Custom Target
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070A12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Custom Target', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        _config.customPriceAlertTarget > 0
                            ? '\$${_config.customPriceAlertTarget.toStringAsFixed(2)}'
                            : 'STANDBY',
                        style: TextStyle(
                          color: _config.customPriceAlertEnabled ? const Color(0xFFF59E0B) : Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        _config.customPriceAlertEnabled ? 'Armed & Active' : 'Standby',
                        style: const TextStyle(color: Colors.white38, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Tile 3: Last Screenshot
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070A12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last Screenshot', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        _alerts.isNotEmpty ? DateFormat('HH:mm:ss').format(_alerts.first.timestamp) : '00:01:04',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                      const Text('Max 20 Stored', style: TextStyle(color: Colors.white38, fontSize: 8)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Screenshot Timeframe, Chart Range & Bar Spacing Selector
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Timeframe Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.timer_outlined, color: Color(0xFFF59E0B), size: 12),
                        SizedBox(width: 4),
                        Text('TIMEFRAME:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5)),
                      ],
                    ),
                    Text(
                      '${_config.chartTimeframe}m active',
                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _timeframes.map((tf) {
                      final cleanTf = tf.replaceAll('M', '');
                      final isSelected = _config.chartTimeframe == cleanTf || _config.chartTimeframe == tf || (_config.chartTimeframe == '15' && tf == '15M') || (_config.chartTimeframe == '5' && tf == '5M');
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _config = PivotConfig(
                              r3: _config.r3,
                              r2: _config.r2,
                              s2: _config.s2,
                              s3: _config.s3,
                              tolerance: _config.tolerance,
                              retriggerDistance: _config.retriggerDistance,
                              chartTimeframe: cleanTf,
                              chartRange: _config.chartRange,
                              barSpacing: _config.barSpacing,
                              telegramAlertsEnabled: _config.telegramAlertsEnabled,
                              autoCalculatePivot: _config.autoCalculatePivot,
                            );
                          });
                          _socketService.updateRemoteConfig({'chartTimeframe': cleanTf});
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF0E1626),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                          ),
                          child: Text(
                            tf,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 10),
                const Divider(color: Color(0xFF1E293B), height: 1),
                const SizedBox(height: 8),

                // 2. Chart Range (1D, 2D, 3D, 5D) & Bar Spacing
                Row(
                  children: [
                    // Range
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.calendar_view_day, color: Color(0xFFF59E0B), size: 11),
                              SizedBox(width: 4),
                              Text('RANGE:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: ['1D', '2D', '3D', '5D'].map((r) {
                              final isSel = _config.chartRange == r;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    final dynamicSpacing = r == '1D' ? 22 : (r == '2D' ? 14 : (r == '3D' ? 9 : 6));
                                    setState(() {
                                      _config = PivotConfig(
                                        r3: _config.r3,
                                        r2: _config.r2,
                                        s2: _config.s2,
                                        s3: _config.s3,
                                        tolerance: _config.tolerance,
                                        retriggerDistance: _config.retriggerDistance,
                                        chartTimeframe: _config.chartTimeframe,
                                        chartRange: r,
                                        barSpacing: dynamicSpacing,
                                        telegramAlertsEnabled: _config.telegramAlertsEnabled,
                                        autoCalculatePivot: _config.autoCalculatePivot,
                                      );
                                    });
                                    _socketService.updateRemoteConfig({'chartRange': r, 'barSpacing': dynamicSpacing});
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF0E1626),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      r,
                                      style: TextStyle(
                                        color: isSel ? Colors.black : Colors.white60,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Bar Spacing Pill
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.zoom_in, color: Color(0xFFF59E0B), size: 11),
                              SizedBox(width: 4),
                              Text('SPACING:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E1626),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${_config.barSpacing}px', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 9, fontFamily: 'monospace')),
                                const Text('Zoom', style: TextStyle(color: Colors.white38, fontSize: 8)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildCompactScreenshotCard(AlertEvent? alert) {
    final hasImage = alert != null && alert.screenshotPath.isNotEmpty;
    final imageUrl = hasImage ? _formatImageUrl(alert.screenshotPath) : '';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.camera_alt, color: Color(0xFFF59E0B), size: 14),
                    SizedBox(width: 6),
                    Text(
                      'TRADINGVIEW CHART SCREENSHOT',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  icon: _isCapturing
                      ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.camera, color: Colors.black, size: 12),
                  label: Text(
                    _isCapturing ? '...' : 'CAPTURE',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _isCapturing ? null : _handleManualCapture,
                ),
              ],
            ),
          ),

          if (hasImage)
            GestureDetector(
              onTap: () => _openScreenshotViewer(alert),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.black,
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B))),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.black,
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.redAccent, size: 24)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.zoom_in, color: Color(0xFFF59E0B), size: 12),
                          SizedBox(width: 3),
                          Text('Pinch to Zoom', style: TextStyle(color: Colors.white, fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 140,
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_size_select_actual_outlined, color: Colors.white24, size: 32),
                    const SizedBox(height: 6),
                    const Text('No screenshot captured yet.', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      icon: const Icon(Icons.camera_alt, color: Color(0xFFF59E0B), size: 14),
                      label: const Text('Capture Chart', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
                      onPressed: _handleManualCapture,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScreenshotsTab() {
    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      body: _alerts.isEmpty
          ? const Center(
              child: Text('No screenshot history yet.', style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _alerts.length,
              itemBuilder: (context, index) {
                final alert = _alerts[index];
                final imageUrl = _formatImageUrl(alert.screenshotPath);
                final dateFormat = DateFormat('HH:mm:ss · dd MMM');

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1626),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => _openScreenshotViewer(alert),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (c, u) => Container(color: Colors.black),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(alert.level, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '\$${alert.currentPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                            Text(
                              dateFormat.format(alert.timestamp),
                              style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              onPressed: () => _socketService.deleteAlert(alert.id),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildAlertsTab() {
    final dateFormat = DateFormat('HH:mm:ss · dd MMM yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      body: _alerts.isEmpty
          ? const Center(
              child: Text('No alert events recorded yet.', style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _alerts.length,
              itemBuilder: (context, index) {
                final alert = _alerts[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1626),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: Text(
                          alert.level,
                          style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Touched Level: \$${alert.currentPrice.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateFormat.format(alert.timestamp),
                              style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen, color: Color(0xFFF59E0B), size: 20),
                        onPressed: () => _openScreenshotViewer(alert),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

