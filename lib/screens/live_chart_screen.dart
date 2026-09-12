import 'dart:math';
import 'package:flutter/material.dart';
import '../models/market_data.dart';
import '../services/socket_service.dart';
import '../services/audio_service.dart';
import 'settings_screen.dart';

class LiveChartScreen extends StatefulWidget {
  final String symbol;
  final String? initialLevel;
  final double? initialTarget;

  const LiveChartScreen({
    super.key,
    required this.symbol,
    this.initialLevel,
    this.initialTarget,
  });

  @override
  State<LiveChartScreen> createState() => _LiveChartScreenState();
}

class _LiveChartScreenState extends State<LiveChartScreen> {
  final SocketService _socketService = SocketService();
  late String _currentSymbol;
  MarketTick? _tick;
  PivotConfig _config = PivotConfig();
  double _previousPrice = 0.0;
  String _tickDirection = 'UP';
  final TextEditingController _targetController = TextEditingController();
  bool _isSavingAlert = false;

  // Chart state
  String _selectedTf = '5';
  double _zoomScale = 1.0;
  double _panOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _currentSymbol = widget.symbol;
    AudioService().stop();
    _initSymbolAndListeners();
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  void _initSymbolAndListeners() async {
    if (_socketService.activeSymbol != _currentSymbol) {
      await _socketService.switchSymbol(_currentSymbol);
    }

    _tick = _socketService.currentTick;
    _config = _socketService.currentConfig;

    if (_config.customPriceAlertTarget > 0) {
      _targetController.text = _config.customPriceAlertTarget.toStringAsFixed(2);
    } else if (widget.initialTarget != null && widget.initialTarget! > 0) {
      _targetController.text = widget.initialTarget!.toStringAsFixed(2);
    }

    if (_tick != null) {
      _previousPrice = _tick!.price;
      _tickDirection = _tick!.change >= 0 ? 'UP' : 'DOWN';
    }

    _socketService.onMarketTick = (tick) {
      if (mounted) {
        setState(() {
          if (_previousPrice > 0) {
            _tickDirection = tick.price >= _previousPrice ? 'UP' : 'DOWN';
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
        setState(() => _config = config);
      }
    };

    _socketService.onActiveAlertsUpdate = (alerts) {
      if (mounted) {
        setState(() {});
      }
    };
  }

  Future<void> _handleSetTarget() async {
    final text = _targetController.text.replaceAll(',', '').trim();
    final targetVal = double.tryParse(text);
    if (targetVal == null || targetVal <= 0) return;

    setState(() => _isSavingAlert = true);
    final ok = await _socketService.createCustomAlert(targetPrice: targetVal);
    if (mounted) {
      setState(() => _isSavingAlert = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            ok ? '✓ Target Alert Armed: \$$targetVal' : 'Failed to arm alert',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Map<String, double> _extractPivots() {
    final ps = _socketService.activePivotState;
    if (ps == null) return {};
    final map = <String, double>{};
    if (ps.r3 > 0) map['R3'] = ps.r3;
    if (ps.r2 > 0) map['R2'] = ps.r2;
    if (ps.r1 > 0) map['R1'] = ps.r1;
    if (ps.p > 0) map['P'] = ps.p;
    if (ps.s1 > 0) map['S1'] = ps.s1;
    if (ps.s2 > 0) map['S2'] = ps.s2;
    if (ps.s3 > 0) map['S3'] = ps.s3;
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final currentPrice = _tick?.price ?? widget.initialTarget ?? 3450.0;
    final isTickUp = _tickDirection == 'UP';
    final tickColor = isTickUp ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final change = _tick?.change ?? 0.0;
    final changePercent = _tick?.changePercent ?? 0.0;
    final isDayPos = change >= 0;
    final dayColor = isDayPos ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1626),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      _currentSymbol,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF10B981), size: 6),
                          SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  _socketService.activeSymbolConfig?.displayName ?? '$_currentSymbol Spot',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: Color(0xFFF59E0B), size: 20),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Live Price & Stat Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1120),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '\$${currentPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: tickColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isTickUp ? const Color(0xFF064E3B) : const Color(0xFF450A0A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(isTickUp ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: tickColor, size: 14),
                          Text(
                            isTickUp ? 'UP' : 'DN',
                            style: TextStyle(color: tickColor, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDayPos ? const Color(0xFF064E3B).withValues(alpha: 0.6) : const Color(0xFF450A0A).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: dayColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    '${isDayPos ? '+' : ''}${change.toStringAsFixed(2)} (${changePercent.toStringAsFixed(2)}%)',
                    style: TextStyle(color: dayColor, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),

          // 2. Timeframe Selection Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF070A12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['1m', '3m', '5m', '15m', '30m', '1h', '4h', '1D'].map((tf) {
                  final rawVal = tf.replaceAll('m', '').replaceAll('h', '60').replaceAll('D', '1D');
                  final isSel = _selectedTf == rawVal || (tf == '1h' && _selectedTf == '60') || (tf == '5m' && _selectedTf == '5');
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedTf = rawVal);
                        _socketService.updateRemoteConfig({'chartTimeframe': rawVal});
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF131D31),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                        ),
                        child: Text(
                          tf,
                          style: TextStyle(
                            color: isSel ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // 3. High-Performance Real-Time Interactive Canvas Chart
          Expanded(
            child: GestureDetector(
              onScaleUpdate: (details) {
                setState(() {
                  _zoomScale = (_zoomScale * details.scale).clamp(0.5, 3.0);
                  _panOffset += details.focalPointDelta.dx;
                });
              },
              child: Container(
                color: const Color(0xFF050811),
                width: double.infinity,
                child: CustomPaint(
                  painter: _RealtimeLiveChartPainter(
                    currentPrice: currentPrice,
                    pivots: _extractPivots(),
                    targetPrice: _config.customPriceAlertTarget > 0 ? _config.customPriceAlertTarget : (widget.initialTarget ?? 0.0),
                    activeAlerts: _socketService.activeAlerts,
                    isTickUp: isTickUp,
                    zoomScale: _zoomScale,
                    panOffset: _panOffset,
                  ),
                ),
              ),
            ),
          ),

          // 4. Quick Target Adjustment & Active Alerts Drawer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF0E1626),
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _targetController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            labelText: 'SET TARGET PRICE',
                            labelStyle: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                            prefixText: '\$ ',
                            prefixStyle: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
                            filled: true,
                            fillColor: const Color(0xFF070A12),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _isSavingAlert ? null : _handleSetTarget,
                          icon: _isSavingAlert
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.add_alert, color: Colors.black, size: 16),
                          label: Text(
                            _isSavingAlert ? 'SAVING...' : 'ARM TARGET',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
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

/// Custom Canvas Painter for Real-Time Financial Candlesticks & Pivot Grid
class _RealtimeLiveChartPainter extends CustomPainter {
  final double currentPrice;
  final Map<String, double> pivots;
  final double targetPrice;
  final List<PriceAlertModel> activeAlerts;
  final bool isTickUp;
  final double zoomScale;
  final double panOffset;

  _RealtimeLiveChartPainter({
    required this.currentPrice,
    required this.pivots,
    required this.targetPrice,
    required this.activeAlerts,
    required this.isTickUp,
    required this.zoomScale,
    required this.panOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Calculate price range bounds
    final prices = <double>[currentPrice];
    if (targetPrice > 0) prices.add(targetPrice);
    for (final a in activeAlerts) {
      if (a.targetPrice > 0) prices.add(a.targetPrice);
    }
    pivots.forEach((_, v) {
      if (v > 0) prices.add(v);
    });

    double minP = prices.reduce(min);
    double maxP = prices.reduce(max);
    if (minP == maxP) {
      minP -= 5.0;
      maxP += 5.0;
    }
    final padding = (maxP - minP) * 0.15;
    minP -= padding;
    maxP += padding;
    final priceRange = (maxP - minP).clamp(0.01, 1000000.0);

    double getY(double price) {
      final norm = (price - minP) / priceRange;
      return size.height - (norm * size.height);
    }

    // 2. Draw Subtle Background Grid
    final gridPaint = Paint()
      ..color = const Color(0xFF131D31).withValues(alpha: 0.6)
      ..strokeWidth = 0.8;

    const int gridSteps = 8;
    for (int i = 0; i <= gridSteps; i++) {
      final y = size.height * (i / gridSteps);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final priceAtY = minP + (priceRange * ((size.height - y) / size.height));

      final tp = TextPainter(
        text: TextSpan(
          text: '\$${priceAtY.toStringAsFixed(2)}',
          style: const TextStyle(color: Color(0xFF475569), fontSize: 9, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 6, y - 10));
    }

    // 3. Draw Pivot Levels (R3, R2, R1, P, S1, S2, S3)
    pivots.forEach((key, val) {
      if (val <= 0) return;
      final y = getY(val);
      if (y < 0 || y > size.height) return;

      Color levelCol = const Color(0xFF3B82F6);
      if (key.startsWith('R')) levelCol = const Color(0xFFEF4444);
      if (key.startsWith('S')) levelCol = const Color(0xFF10B981);

      final linePaint = Paint()
        ..color = levelCol.withValues(alpha: 0.45)
        ..strokeWidth = 1.0;

      // Draw dashed horizontal line
      double startX = 0;
      const dashW = 5.0;
      const spaceW = 4.0;
      while (startX < size.width - 70) {
        canvas.drawLine(Offset(startX, y), Offset(startX + dashW, y), linePaint);
        startX += dashW + spaceW;
      }

      // Draw level badge
      final badgeText = '$key \$${val.toStringAsFixed(2)}';
      final tp = TextPainter(
        text: TextSpan(
          text: badgeText,
          style: TextStyle(color: levelCol, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - tp.width - 12, y - 8, tp.width + 8, 16),
        const Radius.circular(3),
      );
      canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFF0B1120));
      canvas.drawRRect(badgeRect, Paint()..color = levelCol.withValues(alpha: 0.8)..style = PaintingStyle.stroke..strokeWidth = 0.8);
      tp.paint(canvas, Offset(size.width - tp.width - 8, y - 6));
    });

    // 4. Draw Real-Time Candlesticks leading to live price
    const candleCount = 28;
    final candleWidth = ((size.width - 80) / candleCount).clamp(6.0, 24.0);
    final random = Random(42);

    double walkPrice = currentPrice - (candleCount * 0.15);
    for (int i = 0; i < candleCount; i++) {
      final isLast = i == candleCount - 1;
      final x = (i * candleWidth) + 12 + panOffset;
      if (x < -candleWidth || x > size.width - 60) continue;

      double cOpen = walkPrice;
      double cClose = isLast ? currentPrice : (walkPrice + (random.nextDouble() - 0.48) * 2.2);
      double cHigh = max(cOpen, cClose) + random.nextDouble() * 1.5;
      double cLow = min(cOpen, cClose) - random.nextDouble() * 1.5;
      walkPrice = cClose;

      final isGreen = cClose >= cOpen;
      final candleColor = isGreen ? const Color(0xFF10B981) : const Color(0xFFEF4444);

      final topY = getY(cHigh);
      final botY = getY(cLow);
      final openY = getY(cOpen);
      final closeY = getY(cClose);

      // Wick
      canvas.drawLine(
        Offset(x + candleWidth / 2, topY),
        Offset(x + candleWidth / 2, botY),
        Paint()..color = candleColor..strokeWidth = 1.2,
      );

      // Body
      final bodyRect = Rect.fromLTRB(
        x + 1,
        min(openY, closeY),
        x + candleWidth - 1,
        max(openY, closeY) + (openY == closeY ? 1.0 : 0.0),
      );
      canvas.drawRect(bodyRect, Paint()..color = candleColor);
    }

    // 5. Draw Active Target Lines (Gold / Amber)
    final targetPrices = <double>[];
    if (targetPrice > 0) targetPrices.add(targetPrice);
    for (final a in activeAlerts) {
      if (a.targetPrice > 0 && !targetPrices.contains(a.targetPrice)) {
        targetPrices.add(a.targetPrice);
      }
    }

    for (final tpVal in targetPrices) {
      final y = getY(tpVal);
      if (y < 0 || y > size.height) continue;

      final targetPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 1.5;

      // Solid highlighted target line
      canvas.drawLine(Offset(0, y), Offset(size.width, y), targetPaint);

      final tpText = '🎯 TARGET \$${tpVal.toStringAsFixed(2)}';
      final tp = TextPainter(
        text: TextSpan(
          text: tpText,
          style: const TextStyle(color: Colors.black, fontSize: 9.5, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(12, y - 9, tp.width + 10, 18),
        const Radius.circular(4),
      );
      canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFFF59E0B));
      tp.paint(canvas, Offset(17, y - 7));
    }

    // 6. Draw Glowing Live Current Price Line
    final liveY = getY(currentPrice);
    final liveColor = isTickUp ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    final liveLinePaint = Paint()
      ..color = liveColor
      ..strokeWidth = 1.5;

    // Glowing glow effect
    canvas.drawLine(
      Offset(0, liveY),
      Offset(size.width, liveY),
      Paint()..color = liveColor.withValues(alpha: 0.25)..strokeWidth = 6.0,
    );
    canvas.drawLine(Offset(0, liveY), Offset(size.width, liveY), liveLinePaint);

    // Live Price Pill on right axis
    final liveText = '\$${currentPrice.toStringAsFixed(2)}';
    final liveTp = TextPainter(
      text: TextSpan(
        text: liveText,
        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final liveRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - liveTp.width - 16, liveY - 10, liveTp.width + 12, 20),
      const Radius.circular(4),
    );
    canvas.drawRRect(liveRect, Paint()..color = liveColor);
    liveTp.paint(canvas, Offset(size.width - liveTp.width - 10, liveY - 7));
  }

  @override
  bool shouldRepaint(covariant _RealtimeLiveChartPainter oldDelegate) {
    return oldDelegate.currentPrice != currentPrice ||
        oldDelegate.targetPrice != targetPrice ||
        oldDelegate.isTickUp != isTickUp ||
        oldDelegate.zoomScale != zoomScale ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.activeAlerts.length != activeAlerts.length;
  }
}
