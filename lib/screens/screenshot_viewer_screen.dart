import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:intl/intl.dart';
import '../models/market_data.dart';
import '../services/socket_service.dart';

class ScreenshotViewerScreen extends StatelessWidget {
  final AlertEvent event;

  const ScreenshotViewerScreen({Key? key, required this.event}) : super(key: key);

  Color _getLevelColor(String level) {
    if (level.startsWith('R')) return const Color(0xFFEF4444);
    if (level.startsWith('S')) return const Color(0xFF10B981);
    return const Color(0xFFF59E0B);
  }

  String _formatImageUrl(String path) {
    if (path.startsWith('http')) return path;
    final baseUrl = SocketService().serverUrl;
    return '$baseUrl$path';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _formatImageUrl(event.screenshotPath);
    final levelColor = _getLevelColor(event.level);
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
                color: levelColor.withOpacity(0.2),
                border: Border.all(color: levelColor, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                event.level,
                style: TextStyle(
                  color: levelColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '\$${event.currentPrice.toStringAsFixed(2)}',
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
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Delete Screenshot?', style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'Are you sure you want to permanently delete this screenshot alert?',
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
                await SocketService().deleteAlert(event.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Zoomable High-Res TradingView Chart Viewport
          Expanded(
            child: Container(
              color: Colors.black,
              child: PhotoView(
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
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 8),
                      Text('Screenshot unavailable: $error', style: const TextStyle(color: Colors.white60)),
                    ],
                  ),
                ),
              ),
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
                        'Gold Spot / U.S. Dollar (XAU/USD)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.2),
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
                    dateFormat.format(event.timestamp),
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event.triggerReason.isNotEmpty
                        ? event.triggerReason
                        : 'Gold touched ${event.level} @ \$${event.currentPrice.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
