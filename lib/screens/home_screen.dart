import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
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

  bool _isAlertDialogOpen = false;
  final TextEditingController _customTargetPriceController = TextEditingController();
  bool _isSavingCustomAlert = false;
  bool _isEditingActiveTarget = false;

  @override
  void initState() {
    super.initState();
    _initListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().requestPermissions();
    });
  }

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
          if (config.customPriceAlertTarget > 0 && !_isEditingActiveTarget) {
            _customTargetPriceController.text = config.customPriceAlertTarget.toStringAsFixed(2);
          } else if (!config.customPriceAlertEnabled && config.customPriceAlertTarget == 0 && !_isEditingActiveTarget) {
            _customTargetPriceController.clear();
          }
        });
      }
    };

    _socketService.onAlertsUpdate = (alerts) {
      if (mounted) setState(() => _alerts = alerts);
    };

    _socketService.onActiveAlertsUpdate = (activeList) {
      if (mounted) setState(() {});
    };

    _socketService.onLevelStatesUpdate = (states) {
      if (mounted) setState(() {});
    };

    _socketService.onConnectionChange = (connected) {
      if (mounted) setState(() => _isConnected = connected);
    };

    _socketService.onSymbolUpdate = (symbol, symConfig, pivotState) {
      if (mounted) {
        setState(() {
          if (_config.customPriceAlertTarget > 0) {
            _customTargetPriceController.text = _config.customPriceAlertTarget.toStringAsFixed(2);
          } else {
            _customTargetPriceController.clear();
          }
        });
      }
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
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
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

    if (_isAlertDialogOpen) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      _isAlertDialogOpen = false;
    }

    _isAlertDialogOpen = true;
    final isResistance = event.level.toUpperCase().startsWith('R');
    final isSupport = event.level.toUpperCase().startsWith('S');
    final levelColor = isResistance
        ? const Color(0xFFEF4444)
        : (isSupport ? const Color(0xFF10B981) : const Color(0xFFF59E0B));

    final symName = event.displayName.isNotEmpty
        ? event.displayName
        : (event.symbol.isNotEmpty ? event.symbol : 'Target');
    final targetPrice = event.levelPrice > 0 ? event.levelPrice : event.currentPrice;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: levelColor.withValues(alpha: 0.8), width: 2),
            boxShadow: [
              BoxShadow(
                color: levelColor.withValues(alpha: 0.35),
                blurRadius: 30,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black87,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Animated Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: levelColor, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notification_important_rounded, color: levelColor, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'PRICE TOUCH ALERT',
                        style: TextStyle(
                          color: levelColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Symbol Title
                Text(
                  event.symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  symName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 18),

                // Price Information Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070C18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Trigger Level:',
                            style: TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: levelColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              event.level,
                              style: TextStyle(
                                color: levelColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Touch Price:',
                            style: TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                          Text(
                            '\$${event.currentPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: levelColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      if (targetPrice != event.currentPrice && targetPrice > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Target Level:',
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            Text(
                              '\$${targetPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Time:',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          Text(
                            DateFormat('HH:mm:ss · dd MMM yyyy').format(event.timestamp),
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Action Buttons: Cancel and View Chart
                Row(
                  children: [
                    // Cancel Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          AudioService().stop();
                          _isAlertDialogOpen = false;
                          Navigator.of(dialogCtx).pop();
                        },
                        icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                        label: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFF334155)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // View Chart Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          AudioService().stop();
                          _isAlertDialogOpen = false;
                          Navigator.of(dialogCtx).pop();
                          _openScreenshotViewer(event);
                        },
                        icon: const Icon(Icons.candlestick_chart_rounded, size: 18, color: Colors.black),
                        label: const Text(
                          'View Chart',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 4,
                          shadowColor: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

  Future<void> _handleSetCustomPrice() async {
    final text = _customTargetPriceController.text.replaceAll(',', '').trim();
    final targetVal = double.tryParse(text);

    if (targetVal == null || targetVal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('⚠️ Please enter a valid positive target price.'),
        ),
      );
      return;
    }

    setState(() => _isSavingCustomAlert = true);

    final ok = await _socketService.createCustomAlert(
      targetPrice: targetVal,
      condition: 'ANY',
    );

    if (mounted) {
      setState(() {
        _isSavingCustomAlert = false;
        _isEditingActiveTarget = false;
        if (ok) {
          _customTargetPriceController.clear();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.black, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? '✓ TARGET ARMED: \$${targetVal.toStringAsFixed(2)}'
                      : 'Failed to set price alert. Check connection.',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleDeleteAlert(String alertId) async {
    final ok = await _socketService.deleteCustomAlertById(alertId);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            ok ? '✓ Target Alert Removed' : 'Failed to delete alert.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleCancelAlert() async {
    setState(() => _isSavingCustomAlert = true);
    final ok = await _socketService.clearAllCustomAlerts();
    if (mounted) {
      setState(() {
        _customTargetPriceController.clear();
        _isSavingCustomAlert = false;
        _isEditingActiveTarget = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            ok ? '✓ All Custom Alerts Cleared.' : 'Failed to clear alerts.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPrice = _tick?.price ?? 3448.20;
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
          SettingsScreen(
            onBackToMonitor: () {
              if (mounted) setState(() => _currentTabIndex = 0);
            },
          ),
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
          // 1. LIVE SPOT PRICE & CHART CONTROLS CARD
          _buildLivePriceCard(currentPrice),

          const SizedBox(height: 12),

          // 2. REDESIGNED CUSTOM PRICE SET UI & ACTIVE ALERT CARD
          _buildCustomPriceSection(currentPrice),

          const SizedBox(height: 12),

          // 3. COMPACT CHART SCREENSHOT CARD
          _buildCompactScreenshotCard(latestAlert),
        ],
      ),
    );
  }

  Widget _buildLivePriceCard(double price) {
    final change = _tick?.change ?? 0.0;
    final changePercent = _tick?.changePercent ?? 0.0;
    final isDayPos = change >= 0;
    final isTickUp = _tickDirection == 'UP';
    final bid = _tick?.bid ?? (price - 0.25);
    final ask = _tick?.ask ?? (price + 0.25);
    final spread = (ask - bid).abs();

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
          Row(
            children: [
              const Text('Bid: ', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('\$${bid.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Container(width: 1, height: 10, color: Colors.white24),
              const SizedBox(width: 10),
              const Text('Ask: ', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('\$${ask.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Container(width: 1, height: 10, color: Colors.white24),
              const SizedBox(width: 10),
              const Text('Spread: ', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('\$${spread.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          // Chart Settings Toolbar (Timeframe, Range, Spacing)
          _buildChartToolbar(),
        ],
      ),
    );
  }

  Widget _buildChartToolbar() {
    final currentTf = AppTimeframe.fromString(_config.chartTimeframe);
    final currentRange = AppChartRange.fromString(_config.chartRange);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF070A12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: Color(0xFFF59E0B), size: 12),
                  const SizedBox(width: 4),
                  Text('${currentTf.label} · ${currentRange.label}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                child: const Text('ALL SETTINGS ⚙', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...[AppTimeframe.tf1m, AppTimeframe.tf3m, AppTimeframe.tf5m, AppTimeframe.tf15m, AppTimeframe.tf30m, AppTimeframe.tf1h, AppTimeframe.tf4h, AppTimeframe.tf1d].map((tf) {
                  final isSel = currentTf == tf;
                  return InkWell(
                    onTap: () {
                      _socketService.updateRemoteConfig({'chartTimeframe': tf.apiValue});
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF0E1626),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                      ),
                      child: Text(
                        tf.label,
                        style: TextStyle(
                          color: isSel ? Colors.black : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomPriceSection(double currentPrice) {
    final activeList = _socketService.activeAlerts;
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_alert, color: Color(0xFFF59E0B), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MULTI-ALERT ENGINE',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                      ),
                      Text(
                        'Auto-removes on price touch · Push notified',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9.5),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: activeList.isNotEmpty
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: activeList.isNotEmpty ? const Color(0xFF10B981) : Colors.white24,
                  ),
                ),
                child: Text(
                  '${activeList.length} ACTIVE',
                  style: TextStyle(
                    color: activeList.isNotEmpty ? const Color(0xFF10B981) : Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Input Row (Target Price Input & Add Button)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customTargetPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: InputDecoration(
                    labelText: 'ADD TARGET PRICE',
                    labelStyle: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 16),
                    hintText: currentPrice > 0 ? currentPrice.toStringAsFixed(2) : '0.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF070A12),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  icon: _isSavingCustomAlert
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.add, color: Colors.black, size: 18),
                  label: Text(
                    _isSavingCustomAlert ? 'ADDING...' : 'ADD',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: _isSavingCustomAlert ? null : _handleSetCustomPrice,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Quick Increment Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    _customTargetPriceController.text = currentPrice.toStringAsFixed(2);
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.flash_on, color: Color(0xFFF59E0B), size: 12),
                        const SizedBox(width: 2),
                        Text('LIVE (\$${currentPrice.toStringAsFixed(2)})', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ...increments.map((inc) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _buildQuickAdjPill('+${inc >= 1 ? inc.toStringAsFixed(inc.truncateToDouble() == inc ? 0 : 2) : inc.toStringAsFixed(4)}', inc),
                )),
                ...increments.map((inc) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _buildQuickAdjPill('-${inc >= 1 ? inc.toStringAsFixed(inc.truncateToDouble() == inc ? 0 : 2) : inc.toStringAsFixed(4)}', -inc),
                )),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Active Alerts List
          if (activeList.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF070A12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: const Center(
                child: Text(
                  'No active price alerts. Enter target prices above.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ACTIVE TARGETS (Auto-removes on hit):',
                  style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                if (activeList.length > 1)
                  InkWell(
                    onTap: _handleCancelAlert,
                    child: const Text(
                      'CLEAR ALL',
                      style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ...activeList.map((alertItem) {
              final target = alertItem.targetPrice;
              final diff = currentPrice - target;
              final absDiff = diff.abs();
              final isAbove = diff > 0;
              final pct = currentPrice > 0 ? (absDiff / currentPrice) * 100 : 0.0;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF070A12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isAbove ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 14,
                          color: isAbove ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '\$${target.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (alertItem.note.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '· ${alertItem.note}',
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          '${isAbove ? '-' : '+'}\$${absDiff.toStringAsFixed(2)} (${pct.toStringAsFixed(2)}%)',
                          style: TextStyle(
                            color: isAbove ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _handleDeleteAlert(alertItem.id),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.close, color: Color(0xFFEF4444), size: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickAdjPill(String label, double delta) {
    return InkWell(
      onTap: () {
        final current = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? (_tick?.price ?? 3450.0);
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
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
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
