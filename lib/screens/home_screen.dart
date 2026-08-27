import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/market_data.dart';
import '../services/socket_service.dart';
import '../services/audio_service.dart';
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
  bool _isAutoCalculating = false;

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
  }

  void _initListeners() {
    _tick = _socketService.currentTick;
    _config = _socketService.currentConfig;
    _alerts = _socketService.recentAlerts;
    _isConnected = _socketService.isConnected;
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
      if (mounted) setState(() => _config = config);
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
              AudioService().stop();
              Navigator.pop(ctx);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.fullscreen, color: Colors.black, size: 16),
            label: const Text('VIEW CHART', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            onPressed: () {
              AudioService().stop();
              Navigator.pop(ctx);
              _openScreenshotViewer(event);
            },
          ),
        ],
      ),
    );
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

  Future<void> _handleAutoCalcFromLive() async {
    setState(() => _isAutoCalculating = true);
    try {
      final success = await _socketService.autoCalculatePivots();
      if (!success) {
        final tick = _tick;
        final price = tick?.price ?? 4481.17;
        final high = tick?.high ?? (price + 32.0);
        final low = tick?.low ?? (price - 32.0);
        final range = high - low;
        final pivot = (high + low + price) / 3;

        final r3 = double.parse((pivot + 1.000 * range).toStringAsFixed(2));
        final r2 = double.parse((pivot + 0.618 * range).toStringAsFixed(2));
        final s2 = double.parse((pivot - 0.618 * range).toStringAsFixed(2));
        final s3 = double.parse((pivot - 1.000 * range).toStringAsFixed(2));

        await _socketService.updateRemoteConfig({
          'r3': r3,
          'r2': r2,
          's2': s2,
          's3': s3,
          'autoCalculatePivot': true,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✨ Fibonacci levels synchronized: R3: \$${_config.r3}, R2: \$${_config.r2}, S2: \$${_config.s2}, S3: \$${_config.s3}'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAutoCalculating = false);
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

          // 2. ACTIVE PIVOT MONITOR GRID (R3, R2, S2, S3) (MATCHES WEB APP)
          _buildWebStyleTargetLevelsCard(currentPrice),

          const SizedBox(height: 12),

          // 3. COMPACT CHART SCREENSHOT CARD
          _buildCompactScreenshotCard(latestAlert),
        ],
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

              // Tile 2: Active Level
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070A12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Active Level', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('⚡ MONITORING', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.w900)),
                      Text('Auto-Calculated', style: TextStyle(color: Colors.white38, fontSize: 8)),
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

  Widget _buildWebStyleTargetLevelsCard(double currentPrice) {
    final levels = [
      {'key': 'r3', 'name': 'R3', 'label': 'Resistance 3', 'price': _config.r3, 'type': 'RESISTANCE'},
      {'key': 'r2', 'name': 'R2', 'label': 'Resistance 2', 'price': _config.r2, 'type': 'RESISTANCE'},
      {'key': 's2', 'name': 'S2', 'label': 'Support 2', 'price': _config.s2, 'type': 'SUPPORT'},
      {'key': 's3', 'name': 'S3', 'label': 'Support 3', 'price': _config.s3, 'type': 'SUPPORT'},
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Title & Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.gps_fixed, color: Color(0xFFF59E0B), size: 14),
                  const SizedBox(width: 6),
                  const Text(
                    'TARGET LEVELS (R3, R2, S2, S3)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.6),
                  ),
                ],
              ),
              InkWell(
                onTap: _isAutoCalculating ? null : _handleAutoCalcFromLive,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Text(
                    _isAutoCalculating ? '...' : 'Auto-Calc',
                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Legend
          const Row(
            children: [
              _StatusDot(color: Color(0xFFFBBF24), label: 'Ready'),
              SizedBox(width: 8),
              _StatusDot(color: Color(0xFFEF4444), label: 'Touched'),
              SizedBox(width: 8),
              _StatusDot(color: Color(0xFF3B82F6), label: 'Previous'),
            ],
          ),

          const SizedBox(height: 10),

          // 2x2 Grid of Cards (Matching Web App & Eliminating Overflows)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.48,
            ),
            itemCount: levels.length,
            itemBuilder: (context, index) {
              final lvl = levels[index];
              final name = lvl['name'] as String;
              final label = lvl['label'] as String;
              final targetPrice = (lvl['price'] as num).toDouble();
              final distance = (currentPrice - targetPrice).abs();
              final isNear = distance <= _config.tolerance;
              final stateStatus = _socketService.levelStates[name] ?? 'READY';
              final isCompleted = stateStatus == 'COMPLETED';
              final isCurrentlyTouched = (stateStatus == 'TRIGGERED' || isNear) && !isCompleted;
              final isPreviouslyTouched = stateStatus == 'PREVIOUSLY_TOUCHED' && !isCurrentlyTouched && !isCompleted;

              Color cardBg;
              Color cardBorder;
              Color badgeBg;
              Color badgeBorder;
              Color badgeTextColor;
              Color statusPillBg;
              Color statusPillBorder;
              Color statusPillTextColor;
              String statusPillText;
              Color priceColor;
              Color distanceColor;

              if (isCompleted) {
                cardBg = const Color(0xFF581C87).withValues(alpha: 0.25);
                cardBorder = const Color(0xFFA855F7);
                badgeBg = const Color(0xFF7E22CE);
                badgeBorder = const Color(0xFFA855F7);
                badgeTextColor = Colors.white;
                statusPillBg = const Color(0xFF3B0764);
                statusPillBorder = const Color(0xFFA855F7);
                statusPillTextColor = const Color(0xFFE9D5FF);
                statusPillText = '🔒 2/2 LOCKED';
                priceColor = const Color(0xFFE9D5FF);
                distanceColor = const Color(0xFFE9D5FF);
              } else if (isCurrentlyTouched) {
                cardBg = const Color(0xFFEF4444).withValues(alpha: 0.18);
                cardBorder = const Color(0xFFEF4444);
                badgeBg = const Color(0xFFDC2626);
                badgeBorder = const Color(0xFFEF4444);
                badgeTextColor = Colors.white;
                statusPillBg = const Color(0xFFEF4444);
                statusPillBorder = const Color(0xFFEF4444);
                statusPillTextColor = Colors.white;
                statusPillText = '🚨 TOUCHED';
                priceColor = const Color(0xFFF87171);
                distanceColor = const Color(0xFFF87171);
              } else if (isPreviouslyTouched) {
                cardBg = const Color(0xFF3B82F6).withValues(alpha: 0.15);
                cardBorder = const Color(0xFF3B82F6);
                badgeBg = const Color(0xFF2563EB);
                badgeBorder = const Color(0xFF3B82F6);
                badgeTextColor = Colors.white;
                statusPillBg = const Color(0xFF1E3A8A).withValues(alpha: 0.5);
                statusPillBorder = const Color(0xFF3B82F6).withValues(alpha: 0.5);
                statusPillTextColor = const Color(0xFF93C5FD);
                statusPillText = 'PREVIOUS (1/2)';
                priceColor = const Color(0xFF93C5FD);
                distanceColor = const Color(0xFF93C5FD);
              } else {
                cardBg = const Color(0xFF070A12);
                cardBorder = const Color(0xFFF59E0B).withValues(alpha: 0.45);
                badgeBg = const Color(0xFFF59E0B).withValues(alpha: 0.2);
                badgeBorder = const Color(0xFFF59E0B).withValues(alpha: 0.6);
                badgeTextColor = const Color(0xFFF59E0B);
                statusPillBg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
                statusPillBorder = const Color(0xFFF59E0B).withValues(alpha: 0.4);
                statusPillTextColor = const Color(0xFFFBBF24);
                statusPillText = '✓ READY';
                priceColor = const Color(0xFFFBBF24);
                distanceColor = const Color(0xFFFBBF24);
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cardBorder,
                    width: isCurrentlyTouched ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Badge Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: badgeBorder),
                          ),
                          child: Text(
                            name,
                            style: TextStyle(color: badgeTextColor, fontWeight: FontWeight.w900, fontSize: 10),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: statusPillBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: statusPillBorder),
                          ),
                          child: Text(
                            statusPillText,
                            style: TextStyle(
                              color: statusPillTextColor,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Price & Subtitle
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '\$${NumberFormat('#,##0.00').format(targetPrice)}',
                            style: TextStyle(
                              color: priceColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Text(
                          label,
                          style: const TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),

                    // Distance Footer
                    Container(
                      padding: const EdgeInsets.only(top: 2),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Distance:', style: TextStyle(color: Colors.white38, fontSize: 8.5)),
                          Text(
                            '\$${distance.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: distanceColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 9.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
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

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
