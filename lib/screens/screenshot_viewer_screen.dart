import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:intl/intl.dart';
import '../models/market_data.dart';
import '../services/socket_service.dart';
import 'live_chart_screen.dart';

class ScreenshotViewerScreen extends StatefulWidget {
  final AlertEvent event;

  const ScreenshotViewerScreen({super.key, required this.event});

  @override
  State<ScreenshotViewerScreen> createState() => _ScreenshotViewerScreenState();
}

class _ScreenshotViewerScreenState extends State<ScreenshotViewerScreen> {
  late AlertEvent _currentEvent;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _currentEvent = widget.event;
  }

  Color _getLevelColor(String level) {
    if (level.startsWith('R')) return const Color(0xFFEF4444);
    if (level.startsWith('S')) return const Color(0xFF10B981);
    return const Color(0xFFF59E0B);
  }

  String? _getValidImageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final cleanPath = path.trim();
    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      return cleanPath;
    }
    if (cleanPath.startsWith('/')) {
      final baseUrl = SocketService().serverUrl.replaceAll(RegExp(r'/+$'), '');
      return '$baseUrl$cleanPath';
    }
    return null;
  }

  Future<void> _handleCaptureFreshChart() async {
    setState(() => _isCapturing = true);
    try {
      final cfg = SocketService().currentConfig;
      final newEvent = await SocketService().captureScreenshot(
        timeframe: cfg.chartTimeframe,
        range: cfg.chartRange,
        barSpacing: cfg.barSpacing,
      );
      if (mounted && newEvent != null && newEvent.screenshotPath.isNotEmpty) {
        setState(() {
          _currentEvent = newEvent;
          _isCapturing = false;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isCapturing = false);
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _getValidImageUrl(_currentEvent.screenshotPath);
    final levelColor = _getLevelColor(_currentEvent.level);
    final dateFormat = DateFormat('MMM dd, yyyy · HH:mm:ss');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.2),
                border: Border.all(color: levelColor, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _currentEvent.level,
                style: TextStyle(
                  color: levelColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '\$${_currentEvent.currentPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Color(0xFFFBBF24),
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isCapturing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)))
                : const Icon(Icons.refresh, color: Color(0xFFF59E0B)),
            tooltip: 'Refresh Chart',
            onPressed: _isCapturing ? null : _handleCaptureFreshChart,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Delete Alert',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Delete Alert?', style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'Are you sure you want to permanently delete this alert record?',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    TextButton(
                      child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await SocketService().deleteAlert(_currentEvent.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Zoomable High-Res TradingView Chart Viewport or Fallback
          Expanded(
            child: Container(
              color: Colors.black,
              child: imageUrl != null
                  ? PhotoView(
                      imageProvider: CachedNetworkImageProvider(imageUrl),
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 3.0,
                      backgroundDecoration: const BoxDecoration(color: Colors.black),
                      loadingBuilder: (context, event) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: Color(0xFFF59E0B)),
                            const SizedBox(height: 16),
                            Text(
                              'Loading TradingView Chart Screenshot...',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      errorBuilder: (context, error, stackTrace) => _buildFallbackChartCard(),
                    )
                  : _buildFallbackChartCard(),
            ),
          ),

          // Metadata Bottom Drawer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _currentEvent.displayName.isNotEmpty
                            ? _currentEvent.displayName
                            : (_currentEvent.symbol.isNotEmpty ? _currentEvent.symbol : 'Multi-Asset Terminal'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '✓ SENT TO TELEGRAM',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateFormat.format(_currentEvent.timestamp),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentEvent.triggerReason.isNotEmpty
                        ? _currentEvent.triggerReason
                        : '${_currentEvent.displayName.isNotEmpty ? _currentEvent.displayName : (_currentEvent.symbol.isNotEmpty ? _currentEvent.symbol : "Asset")} touched ${_currentEvent.level} @ \$${_currentEvent.currentPrice.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackChartCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.candlestick_chart_outlined, color: Color(0xFFF59E0B), size: 48),
              const SizedBox(height: 12),
              Text(
                '${_currentEvent.symbol} PRICE TOUCH EVENT',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                'Price @ \$${_currentEvent.currentPrice.toStringAsFixed(2)} (Target: \$${_currentEvent.levelPrice.toStringAsFixed(2)})',
                style: const TextStyle(color: Color(0xFFFBBF24), fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                icon: const Icon(Icons.show_chart, color: Colors.black, size: 16),
                label: const Text(
                  'OPEN LIVE REAL-TIME CHART',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveChartScreen(
                        symbol: _currentEvent.symbol,
                        initialLevel: _currentEvent.level,
                        initialTarget: _currentEvent.levelPrice > 0 ? _currentEvent.levelPrice : _currentEvent.currentPrice,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: _isCapturing
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)))
                    : const Icon(Icons.camera_alt, color: Color(0xFFF59E0B), size: 14),
                label: Text(
                  _isCapturing ? 'GENERATING...' : 'Capture Static Snapshot',
                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11),
                ),
                onPressed: _isCapturing ? null : _handleCaptureFreshChart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
