import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/market_data.dart';
import '../services/socket_service.dart';
import '../services/audio_service.dart';
import 'screenshot_viewer_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

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

    _socketService.onMarketTick = (tick) {
      if (mounted) setState(() => _tick = tick);
    };

    _socketService.onConfigUpdate = (config) {
      if (mounted) setState(() => _config = config);
    };

    _socketService.onAlertsUpdate = (alerts) {
      if (mounted) setState(() => _alerts = alerts);
    };

    _socketService.onConnectionChange = (connected) {
      if (mounted) setState(() => _isConnected = connected);
    };

    _socketService.onAlertTriggered = (event) {
      if (mounted) {
        _showIncomingAlertDialog(event);
      }
    };
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
              'Gold touched ${event.level} at \$${event.currentPrice.toStringAsFixed(2)}',
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

  @override
  Widget build(BuildContext context) {
    final currentPrice = _tick?.price ?? 4356.40;
    final latestAlertWithImage = _alerts.isNotEmpty ? _alerts.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1626),
        elevation: 0,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.show_chart, color: Color(0xFFF59E0B), size: 18),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'GOLD (XAU/USD)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
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
        actions: [
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
          // 1. LIVE SPOT PRICE TICKER
          _buildLivePriceCard(currentPrice),

          const SizedBox(height: 10),

          // 2. ACTIVE PIVOT MONITOR GRID (R3, R2, S2, S3)
          _buildPivotLevelsGrid(currentPrice),

          const SizedBox(height: 10),

          // 3. COMPACT CHART SCREENSHOT CARD
          _buildCompactScreenshotCard(latestAlert),
        ],
      ),
    );
  }

  Widget _buildLivePriceCard(double price) {
    final change = _tick?.change ?? 0.0;
    final changePercent = _tick?.changePercent ?? 0.0;
    final isPos = change >= 0;
    final high = _tick?.high ?? (price + 8.0);
    final low = _tick?.low ?? (price - 8.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SPOT PRICE (XAU/USD)', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: (isPos ? Colors.greenAccent : Colors.redAccent).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isPos ? Colors.greenAccent : Colors.redAccent, width: 1),
                ),
                child: Text(
                  '${isPos ? '+' : ''}\$${change.toStringAsFixed(2)} (${isPos ? '+' : ''}${changePercent.toStringAsFixed(2)}%)',
                  style: TextStyle(
                    color: isPos ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('24H HIGH: \$${high.toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                Text('24H LOW: \$${low.toStringAsFixed(2)}', style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPivotLevelsGrid(double currentPrice) {
    final levels = [
      {'name': 'R3', 'price': _config.r3, 'color': const Color(0xFFF59E0B)},
      {'name': 'R2', 'price': _config.r2, 'color': const Color(0xFFF97316)},
      {'name': 'S2', 'price': _config.s2, 'color': const Color(0xFF10B981)},
      {'name': 'S3', 'price': _config.s3, 'color': const Color(0xFF14B8A6)},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ACTIVE PIVOT MONITOR (R3, R2, S2, S3)',
              style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.8),
            ),
            Text(
              '±\$${_config.tolerance.toStringAsFixed(2)} Tol',
              style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.3,
          ),
          itemCount: levels.length,
          itemBuilder: (context, index) {
            final lvl = levels[index];
            final name = lvl['name'] as String;
            final targetPrice = (lvl['price'] as num).toDouble();
            final color = lvl['color'] as Color;
            final diff = targetPrice - currentPrice;
            final absDiff = (currentPrice - targetPrice).abs();
            final isTouching = absDiff <= _config.tolerance;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isTouching ? const Color(0xFFEF4444).withOpacity(0.2) : const Color(0xFF0E1626),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isTouching ? const Color(0xFFEF4444) : color.withOpacity(0.4),
                  width: isTouching ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${targetPrice.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: isTouching ? Colors.redAccent : Colors.white10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          isTouching ? 'TOUCHING' : 'READY',
                          style: TextStyle(
                            color: isTouching ? Colors.white : Colors.white60,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${diff >= 0 ? '+' : ''}\$${diff.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isTouching ? Colors.redAccent : Colors.white54,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCompactScreenshotCard(AlertEvent? alert) {
    final hasImage = alert != null && alert.screenshotPath.isNotEmpty;
    final imageUrl = hasImage ? _formatImageUrl(alert.screenshotPath) : '';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(14),
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
                        color: Colors.black.withOpacity(0.8),
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
                                    color: const Color(0xFFF59E0B).withOpacity(0.2),
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
                          color: const Color(0xFFF59E0B).withOpacity(0.2),
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
