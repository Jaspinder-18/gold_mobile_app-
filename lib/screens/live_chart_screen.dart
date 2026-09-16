import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:webview_flutter/webview_flutter.dart';
import '../models/market_data.dart';
import '../services/socket_service.dart';
import '../services/audio_service.dart';
import 'settings_screen.dart';

class LiveChartScreen extends StatefulWidget {
  final String symbol;
  final String? initialLevel;
  final double? initialTarget;
  final double? touchPrice;
  final DateTime? touchTimestamp;
  final bool isEmbedded;

  const LiveChartScreen({
    super.key,
    required this.symbol,
    this.initialLevel,
    this.initialTarget,
    this.touchPrice,
    this.touchTimestamp,
    this.isEmbedded = false,
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
  double? _touchPrice;
  DateTime? _touchTimestamp;
  String? _touchLevel;

  // Chart & WebView state
  late final WebViewController _webViewController;
  bool _isLoadingChart = true;
  String _selectedTf = '15';
  bool _isFullscreen = false;
  bool _showPivotChips = true;

  // Callback references for clean subscription lifecycle
  late final Function(MarketTick) _tickListener;
  late final Function(PivotConfig) _configListener;
  late final Function(List<PriceAlertModel>) _activeAlertsListener;

  final List<Map<String, String>> _timeframes = [
    {'label': '1m', 'value': '1'},
    {'label': '3m', 'value': '3'},
    {'label': '5m', 'value': '5'},
    {'label': '15m', 'value': '15'},
    {'label': '30m', 'value': '30'},
    {'label': '1h', 'value': '60'},
    {'label': '4h', 'value': '240'},
    {'label': '1D', 'value': 'D'},
  ];

  @override
  void initState() {
    super.initState();
    _currentSymbol = widget.symbol.toUpperCase();
    _touchPrice = widget.touchPrice ?? widget.initialTarget;
    _touchTimestamp = widget.touchTimestamp;
    _touchLevel = widget.initialLevel;
    AudioService().stop();

    _initWebViewController();
    _setupListeners();
  }

  @override
  void dispose() {
    _socketService.removeMarketTickListener(_tickListener);
    _socketService.removeConfigListener(_configListener);
    _socketService.removeActiveAlertsListener(_activeAlertsListener);
    _targetController.dispose();
    super.dispose();
  }

  String _getTradingViewTicker(String symbol) {
    final sym = symbol.toUpperCase().trim();
    final cfg = _socketService.activeSymbolConfig;
    if (cfg != null && cfg.tradingViewTicker.isNotEmpty) {
      return cfg.tradingViewTicker;
    }
    if (sym == 'XAUUSD' || sym == 'GOLD') return 'OANDA:XAUUSD';
    if (sym == 'XAGUSD' || sym == 'SILVER') return 'TVC:SILVER';
    if (sym == 'BTCUSD' || sym == 'BTCUSDT') return 'BINANCE:BTCUSDT';
    if (sym == 'ETHUSD' || sym == 'ETHUSDT') return 'BINANCE:ETHUSDT';
    if (sym == 'EURUSD') return 'FX_IDC:EURUSD';
    if (sym == 'GBPUSD') return 'FX_IDC:GBPUSD';
    if (sym == 'USDJPY') return 'FX_IDC:USDJPY';
    if (sym == 'AUDUSD') return 'FX_IDC:AUDUSD';
    if (sym == 'USDCAD') return 'FX_IDC:USDCAD';
    if (sym == 'US30' || sym == 'DJI') return 'DJ:DJI';
    if (sym == 'SPX500' || sym == 'SPX') return 'SP:SPX';
    if (sym == 'NAS100' || sym == 'NDX') return 'NASDAQ:NDX';
    if (sym == 'NIFTY') return 'NSE:NIFTY';
    if (sym == 'BANKNIFTY') return 'NSE:BANKNIFTY';
    if (sym == 'CRUDEOIL' || sym == 'USOIL') return 'TVC:USOIL';
    return 'OANDA:$sym';
  }

  String _buildTradingViewHtml(String symbol, String interval) {
    final tvTicker = _getTradingViewTicker(symbol);
    final htmlContent = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>TradingView Chart</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%;
      height: 100%;
      overflow: hidden;
      background-color: #030712;
      color: #f8fafc;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    #tv_chart_container {
      width: 100%;
      height: 100%;
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
    }
    #loading_indicator {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      color: #f59e0b;
      font-family: monospace;
      font-size: 13px;
      font-weight: bold;
      display: flex;
      align-items: center;
      gap: 10px;
      z-index: 10;
      background: rgba(3, 7, 18, 0.85);
      padding: 12px 20px;
      border-radius: 8px;
      border: 1px solid rgba(245, 158, 11, 0.3);
    }
    .spinner {
      width: 20px;
      height: 20px;
      border: 2.5px solid rgba(245, 158, 11, 0.2);
      border-top-color: #f59e0b;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  </style>
  <script type="text/javascript" src="https://s3.tradingview.com/tv.js"></script>
</head>
<body>
  <div id="loading_indicator">
    <div class="spinner"></div>
    <span>Connecting TradingView $tvTicker...</span>
  </div>
  <div id="tv_chart_container"></div>
  <script type="text/javascript">
    function initTradingView() {
      try {
        new TradingView.widget({
          "autosize": true,
          "symbol": "$tvTicker",
          "interval": "$interval",
          "timezone": "Asia/Kolkata",
          "theme": "dark",
          "style": "1",
          "locale": "en",
          "toolbar_bg": "#030712",
          "enable_publishing": false,
          "allow_symbol_change": false,
          "container_id": "tv_chart_container",
          "hide_side_toolbar": false,
          "save_image": true,
          "studies": [
            "Volume@tv-basicstudies"
          ],
          "overrides": {
            "mainSeriesProperties.candleStyle.upColor": "#10b981",
            "mainSeriesProperties.candleStyle.downColor": "#ef4444",
            "mainSeriesProperties.candleStyle.borderUpColor": "#10b981",
            "mainSeriesProperties.candleStyle.borderDownColor": "#ef4444",
            "mainSeriesProperties.candleStyle.wickUpColor": "#10b981",
            "mainSeriesProperties.candleStyle.wickDownColor": "#ef4444",
            "paneProperties.background": "#030712",
            "paneProperties.vertGridProperties.color": "rgba(255, 255, 255, 0.04)",
            "paneProperties.horzGridProperties.color": "rgba(255, 255, 255, 0.04)"
          }
        });
        setTimeout(function() {
          var loader = document.getElementById('loading_indicator');
          if (loader) loader.style.display = 'none';
        }, 1500);
      } catch (err) {
        console.error("TradingView init error:", err);
      }
    }

    if (window.TradingView) {
      initTradingView();
    } else {
      window.onload = initTradingView;
    }
  </script>
</body>
</html>
''';
    return htmlContent;
  }

  void _initWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF030712))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress >= 80 && _isLoadingChart) {
              if (mounted) setState(() => _isLoadingChart = false);
            }
          },
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoadingChart = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoadingChart = false);
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) setState(() => _isLoadingChart = false);
          },
        ),
      );
    _loadChartHtml();
  }

  void _loadChartHtml() {
    final html = _buildTradingViewHtml(_currentSymbol, _selectedTf);
    _webViewController.loadHtmlString(html, baseUrl: 'https://s3.tradingview.com');
  }

  void _setupListeners() async {
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

    _tickListener = (tick) {
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
    _socketService.addMarketTickListener(_tickListener);

    _configListener = (config) {
      if (mounted) setState(() => _config = config);
    };
    _socketService.addConfigListener(_configListener);

    _activeAlertsListener = (alerts) {
      if (mounted) setState(() {});
    };
    _socketService.addActiveAlertsListener(_activeAlertsListener);
  }

  void _switchTimeframe(String tfValue) {
    if (_selectedTf == tfValue) return;
    setState(() {
      _selectedTf = tfValue;
      _isLoadingChart = true;
    });
    _socketService.updateRemoteConfig({'chartTimeframe': tfValue});
    _loadChartHtml();
  }

  Future<void> _handleSetTarget([double? explicitValue]) async {
    double? targetVal = explicitValue;
    if (targetVal == null) {
      final text = _targetController.text.replaceAll(',', '').trim();
      targetVal = double.tryParse(text);
    }
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

  void _adjustTarget(double delta) {
    final current = double.tryParse(_targetController.text.replaceAll(',', '').trim()) ?? (_tick?.price ?? 4000.0);
    final updated = (current + delta).clamp(0.01, 1000000.0);
    _targetController.text = updated.toStringAsFixed(2);
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
    final currentPrice = _tick?.price ?? widget.initialTarget ?? 4289.14;
    final isTickUp = _tickDirection == 'UP';
    final tickColor = isTickUp ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final change = _tick?.change ?? 0.0;
    final changePercent = _tick?.changePercent ?? 0.0;
    final isDayPos = change >= 0;
    final dayColor = isDayPos ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final pivots = _extractPivots();

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      // In fullscreen, we do NOT use standard AppBar; instead we render a sleek in-body control bar inside SafeArea
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF090E1A),
              elevation: 0,
              automaticallyImplyLeading: !widget.isEmbedded,
              leading: widget.isEmbedded
                  ? null
                  : IconButton(
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
                                  'LIVE TV',
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
                  icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                  tooltip: 'Reload Chart',
                  onPressed: () {
                    setState(() => _isLoadingChart = true);
                    _loadChartHtml();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen, color: Color(0xFFF59E0B), size: 24),
                  tooltip: 'Fullscreen Chart',
                  onPressed: () => setState(() => _isFullscreen = true),
                ),
                IconButton(
                  icon: const Icon(Icons.tune, color: Color(0xFFF59E0B), size: 20),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
      // SafeArea is ALWAYS strictly applied on all sides (protecting against camera notch, punch hole, and status bar)
      body: SafeArea(
        top: true,
        bottom: true,
        left: true,
        right: true,
        child: Column(
          children: [
            // ================= FULLSCREEN TOP CONTROL BAR =================
            if (_isFullscreen)
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFF090E1A),
                  border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back & Symbol Chip
                    Row(
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                          onPressed: () => setState(() => _isFullscreen = false),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _currentSymbol,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '\$${NumberFormat('#,##0.00').format(currentPrice)}',
                          style: TextStyle(
                            color: tickColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),

                    // Quick Timeframes & Exit Fullscreen Button
                    Row(
                      children: [
                        ...['1m', '5m', '15m', '1h', '1D'].map((tf) {
                          final rawVal = tf.replaceAll('m', '').replaceAll('h', '60');
                          final isSel = _selectedTf == rawVal;
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: InkWell(
                              onTap: () => _switchTimeframe(rawVal),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF131D31),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                                ),
                                child: Text(
                                  tf,
                                  style: TextStyle(
                                    color: isSel ? Colors.black : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: 4),
                        // Dedicated Exit Fullscreen Button
                        ElevatedButton.icon(
                          icon: const Icon(Icons.fullscreen_exit, color: Colors.black, size: 14),
                          label: const Text(
                            'EXIT',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => setState(() => _isFullscreen = false),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // ================= NORMAL VIEW HEADER SECTIONS =================
            if (!_isFullscreen) ...[
              // 1. Live Price & Stat Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF090E1A),
                  border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          '\$${NumberFormat('#,##0.00').format(currentPrice)}',
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
                color: const Color(0xFF030712),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _timeframes.map((tf) {
                            final isSel = _selectedTf == tf['value'];
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () => _switchTimeframe(tf['value']!),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF131D31),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                                  ),
                                  child: Text(
                                    tf['label']!,
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
                    if (pivots.isNotEmpty)
                      InkWell(
                        onTap: () => setState(() => _showPivotChips = !_showPivotChips),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: _showPivotChips ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.layers_outlined, color: Color(0xFFF59E0B), size: 13),
                              const SizedBox(width: 4),
                              Text(
                                _showPivotChips ? 'PIVOTS' : 'HIDE',
                                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 2.1 Pivot Level Reference Strip (Fibonacci / Traditional Levels)
              if (_showPivotChips && pivots.isNotEmpty)
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: const Color(0xFF050811),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: pivots.entries.map((e) {
                      Color chipCol = const Color(0xFF3B82F6);
                      if (e.key.startsWith('R')) chipCol = const Color(0xFFEF4444);
                      if (e.key.startsWith('S')) chipCol = const Color(0xFF10B981);
                      return Container(
                        margin: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: chipCol.withValues(alpha: 0.6), width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Text(
                              e.key,
                              style: TextStyle(color: chipCol, fontSize: 9.5, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '\$${e.value.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],

            // ================= TRADINGVIEW ADVANCED CHART WEBVIEW =================
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _webViewController),
                  if (_isLoadingChart)
                    Container(
                      color: const Color(0xFF030712),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: Color(0xFFF59E0B), strokeWidth: 3),
                            const SizedBox(height: 14),
                            Text(
                              'Loading TradingView Live Chart (${_getTradingViewTicker(_currentSymbol)})...',
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ================= NORMAL VIEW FOOTER SECTIONS =================
            if (!_isFullscreen) ...[
              // 4. White Line Touch Notification Info Banner (if navigated from alert)
              if (_touchPrice != null && _touchPrice! > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.08),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.touch_app_rounded, color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'WHITE LINE TOUCH: \$${_touchPrice!.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                                if (_touchLevel != null && _touchLevel!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _touchLevel!,
                                      style: const TextStyle(color: Colors.black, fontSize: 9.5, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_filled, color: Colors.white70, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      formatIstDateTime(_touchTimestamp ?? DateTime.now()),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Live: \$${currentPrice.toStringAsFixed(2)} (${(currentPrice - _touchPrice!) >= 0 ? '+' : ''}${(currentPrice - _touchPrice!).toStringAsFixed(2)})',
                                  style: TextStyle(
                                    color: (currentPrice - _touchPrice!) >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 5. Quick Target Price Arming Controls
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
                      // Quick Adjustment Steppers
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'QUICK STEPPERS:',
                              style: TextStyle(color: Colors.white38, fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                            Row(
                              children: [-10.0, -1.0, 1.0, 10.0].map((step) {
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: InkWell(
                                    onTap: () => _adjustTarget(step),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF131D31),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF1E293B)),
                                      ),
                                      child: Text(
                                        '${step > 0 ? '+' : ''}${step.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: step > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                          fontSize: 10,
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
                              onPressed: _isSavingAlert ? null : () => _handleSetTarget(),
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
          ],
        ),
      ),
    );
  }
}
