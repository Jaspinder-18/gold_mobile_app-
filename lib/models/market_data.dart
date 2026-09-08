double _toDouble(dynamic val, [double fallback = 0.0]) {
  if (val == null) return fallback;
  if (val is num) return val.toDouble();
  if (val is String) {
    return double.tryParse(val) ?? fallback;
  }
  return fallback;
}

int _toInt(dynamic val, [int fallback = 0]) {
  if (val == null) return fallback;
  if (val is num) return val.toInt();
  if (val is String) {
    return int.tryParse(val) ?? fallback;
  }
  return fallback;
}

bool _toBool(dynamic val, [bool fallback = false]) {
  if (val == null) return fallback;
  if (val is bool) return val;
  if (val is String) {
    final lower = val.toLowerCase().trim();
    if (lower == 'true' || lower == '1' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
  }
  if (val is num) return val != 0;
  return fallback;
}

class MarketTick {
  final String symbol;
  final String displayName;
  final double price;
  final double bid;
  final double ask;
  final double high;
  final double low;
  final double open;
  final double change;
  final double changePercent;
  final DateTime timestamp;

  MarketTick({
    required this.symbol,
    this.displayName = 'Gold / USD Spot',
    required this.price,
    required this.bid,
    required this.ask,
    required this.high,
    required this.low,
    required this.open,
    required this.change,
    required this.changePercent,
    required this.timestamp,
  });

  factory MarketTick.fromJson(Map<String, dynamic> json) {
    final p = _toDouble(json['price'], 4356.40);
    return MarketTick(
      symbol: json['symbol']?.toString() ?? json['rawSymbol']?.toString() ?? 'XAUUSD',
      displayName: json['displayName']?.toString() ?? json['symbol']?.toString() ?? 'Gold / USD',
      price: p,
      bid: _toDouble(json['bid'], p - 0.25),
      ask: _toDouble(json['ask'], p + 0.25),
      high: _toDouble(json['high'] ?? json['high24h'], 4370.00),
      low: _toDouble(json['low'] ?? json['low24h'], 4340.00),
      open: _toDouble(json['open'], 4350.00),
      change: _toDouble(json['change'], 0.0),
      changePercent: _toDouble(json['changePercent'], 0.0),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

enum AppTimeframe {
  tf1m('1m', '1', '1 Minute'),
  tf2m('2m', '2', '2 Minutes'),
  tf3m('3m', '3', '3 Minutes'),
  tf4m('4m', '4', '4 Minutes'),
  tf5m('5m', '5', '5 Minutes'),
  tf10m('10m', '10', '10 Minutes'),
  tf15m('15m', '15', '15 Minutes'),
  tf30m('30m', '30', '30 Minutes'),
  tf1h('1h', '60', '1 Hour'),
  tf2h('2h', '120', '2 Hours'),
  tf4h('4h', '240', '4 Hours'),
  tf1d('1D', '1D', '1 Day'),
  tf2d('2D', '2D', '2 Days'),
  tf3d('3D', '3D', '3 Days'),
  tf4d('4D', '4D', '4 Days'),
  tf5d('5D', '5D', '5 Days');

  final String label;
  final String apiValue;
  final String fullTitle;
  const AppTimeframe(this.label, this.apiValue, this.fullTitle);

  static AppTimeframe fromString(String? val) {
    if (val == null) return AppTimeframe.tf15m;
    final clean = val.trim().toUpperCase().replaceAll('MINUTES', '').replaceAll('MIN', '').replaceAll('M', 'm').replaceAll('HOUR', 'h').replaceAll('H', 'h').replaceAll('DAY', 'D').replaceAll('DAYS', 'D').trim();
    for (final tf in AppTimeframe.values) {
      if (tf.label.toUpperCase() == clean.toUpperCase() || tf.apiValue.toUpperCase() == clean.toUpperCase()) {
        return tf;
      }
    }
    if (clean == '1') return AppTimeframe.tf1m;
    if (clean == '2') return AppTimeframe.tf2m;
    if (clean == '3') return AppTimeframe.tf3m;
    if (clean == '4') return AppTimeframe.tf4m;
    if (clean == '5') return AppTimeframe.tf5m;
    if (clean == '10') return AppTimeframe.tf10m;
    if (clean == '15') return AppTimeframe.tf15m;
    if (clean == '30') return AppTimeframe.tf30m;
    if (clean == '60' || clean == '1H') return AppTimeframe.tf1h;
    if (clean == '120' || clean == '2H') return AppTimeframe.tf2h;
    if (clean == '240' || clean == '4H') return AppTimeframe.tf4h;
    if (clean == 'D' || clean == '1D') return AppTimeframe.tf1d;
    if (clean == '2D') return AppTimeframe.tf2d;
    if (clean == '3D') return AppTimeframe.tf3d;
    if (clean == '4D') return AppTimeframe.tf4d;
    if (clean == '5D') return AppTimeframe.tf5d;
    return AppTimeframe.tf15m;
  }
}

enum AppChartRange {
  r1d('1D', '1 Day', 1),
  r2d('2D', '2 Days', 2),
  r3d('3D', '3 Days', 3),
  r4d('4D', '4 Days', 4),
  r5d('5D', '5 Days', 5);

  final String label;
  final String title;
  final int days;
  const AppChartRange(this.label, this.title, this.days);

  static AppChartRange fromString(String? val) {
    if (val == null) return AppChartRange.r1d;
    final upper = val.toUpperCase().trim();
    for (final r in AppChartRange.values) {
      if (r.label == upper || r.days.toString() == upper.replaceAll('D', '')) {
        return r;
      }
    }
    return AppChartRange.r1d;
  }
}

enum AppBarSpacing {
  veryCompact('Very Compact', 6),
  compact('Compact', 10),
  normal('Normal', 16),
  wide('Wide', 22),
  veryWide('Very Wide', 28);

  final String label;
  final int px;
  const AppBarSpacing(this.label, this.px);

  static AppBarSpacing fromValue(dynamic val) {
    final numVal = _toInt(val, 16);
    if (numVal <= 7) return AppBarSpacing.veryCompact;
    if (numVal <= 12) return AppBarSpacing.compact;
    if (numVal <= 18) return AppBarSpacing.normal;
    if (numVal <= 24) return AppBarSpacing.wide;
    return AppBarSpacing.veryWide;
  }
}

class PivotConfig {
  final double r3;
  final double r2;
  final double s2;
  final double s3;
  final double tolerance;
  final double retriggerDistance;
  final String chartTimeframe;
  final String chartRange;
  final int barSpacing;
  final bool telegramAlertsEnabled;
  final bool autoCalculatePivot;
  final int autoCalcIntervalMinutes;
  final bool customPriceAlertEnabled;
  final double customPriceAlertTarget;
  final String customPriceAlertStatus;

  PivotConfig({
    this.r3 = 4657.02,
    this.r2 = 4580.75,
    this.s2 = 4333.97,
    this.s3 = 4257.70,
    this.tolerance = 0.20,
    this.retriggerDistance = 1.00,
    this.chartTimeframe = '15',
    this.chartRange = '1D',
    this.barSpacing = 16,
    this.telegramAlertsEnabled = true,
    this.autoCalculatePivot = false,
    this.autoCalcIntervalMinutes = 15,
    this.customPriceAlertEnabled = false,
    this.customPriceAlertTarget = 0.0,
    this.customPriceAlertStatus = 'INACTIVE',
  });

  factory PivotConfig.fromJson(Map<String, dynamic> json) {
    return PivotConfig(
      r3: _toDouble(json['r3'], 4657.017),
      r2: _toDouble(json['r2'], 4580.747),
      s2: _toDouble(json['s2'], 4333.967),
      s3: _toDouble(json['s3'], 4257.697),
      tolerance: _toDouble(json['tolerance'], 0.20),
      retriggerDistance: _toDouble(json['retriggerDistance'], 1.00),
      chartTimeframe: json['chartTimeframe']?.toString() ?? '15',
      chartRange: json['chartRange']?.toString() ?? '1D',
      barSpacing: _toInt(json['barSpacing'], 16),
      telegramAlertsEnabled: _toBool(json['telegramAlertsEnabled'], true),
      autoCalculatePivot: _toBool(json['autoCalculatePivot'], false),
      autoCalcIntervalMinutes: _toInt(json['autoCalcIntervalMinutes'], 15),
      customPriceAlertEnabled: _toBool(json['customPriceAlertEnabled'], false),
      customPriceAlertTarget: _toDouble(json['customPriceAlertTarget'], 0.0),
      customPriceAlertStatus: json['customPriceAlertStatus']?.toString() ??
          (_toBool(json['customPriceAlertEnabled'], false) && _toDouble(json['customPriceAlertTarget'], 0.0) > 0 ? 'ACTIVE' : 'INACTIVE'),
    );
  }

  PivotConfig copyWith({
    double? r3,
    double? r2,
    double? s2,
    double? s3,
    double? tolerance,
    double? retriggerDistance,
    String? chartTimeframe,
    String? chartRange,
    int? barSpacing,
    bool? telegramAlertsEnabled,
    bool? autoCalculatePivot,
    int? autoCalcIntervalMinutes,
    bool? customPriceAlertEnabled,
    double? customPriceAlertTarget,
    String? customPriceAlertStatus,
  }) {
    return PivotConfig(
      r3: r3 ?? this.r3,
      r2: r2 ?? this.r2,
      s2: s2 ?? this.s2,
      s3: s3 ?? this.s3,
      tolerance: tolerance ?? this.tolerance,
      retriggerDistance: retriggerDistance ?? this.retriggerDistance,
      chartTimeframe: chartTimeframe ?? this.chartTimeframe,
      chartRange: chartRange ?? this.chartRange,
      barSpacing: barSpacing ?? this.barSpacing,
      telegramAlertsEnabled: telegramAlertsEnabled ?? this.telegramAlertsEnabled,
      autoCalculatePivot: autoCalculatePivot ?? this.autoCalculatePivot,
      autoCalcIntervalMinutes: autoCalcIntervalMinutes ?? this.autoCalcIntervalMinutes,
      customPriceAlertEnabled: customPriceAlertEnabled ?? this.customPriceAlertEnabled,
      customPriceAlertTarget: customPriceAlertTarget ?? this.customPriceAlertTarget,
      customPriceAlertStatus: customPriceAlertStatus ?? this.customPriceAlertStatus,
    );
  }
}


class AlertEvent {
  final String id;
  final String symbol;
  final String displayName;
  final String level;
  final double levelPrice;
  final double currentPrice;
  final double tolerance;
  final String screenshotPath;
  final String triggerReason;
  final String telegramStatus;
  final DateTime timestamp;
  final bool isTest;

  AlertEvent({
    required this.id,
    required this.symbol,
    this.displayName = 'Gold / USD Spot',
    required this.level,
    required this.levelPrice,
    required this.currentPrice,
    required this.tolerance,
    required this.screenshotPath,
    required this.triggerReason,
    required this.telegramStatus,
    required this.timestamp,
    this.isTest = false,
  });

  factory AlertEvent.fromJson(Map<String, dynamic> rawJson) {
    final json = (rawJson['event'] != null && rawJson['event'] is Map)
        ? Map<String, dynamic>.from(rawJson['event'] as Map)
        : rawJson;

    final rawLevel = json['level']?.toString() ?? 'CUSTOM';
    final targetPrice = _toDouble(json['levelPrice'] ?? json['customPrice'] ?? json['targetPrice'], 0.0);
    final curPrice = _toDouble(json['currentPrice'] ?? json['triggerPrice'] ?? json['price'], targetPrice);

    return AlertEvent(
      id: (json['_id'] ?? json['id'] ?? json['eventId'] ?? 'evt_${DateTime.now().millisecondsSinceEpoch}').toString(),
      symbol: json['symbol']?.toString() ?? 'XAUUSD',
      displayName: json['displayName']?.toString() ?? json['symbol']?.toString() ?? 'Gold / USD',
      level: rawLevel,
      levelPrice: targetPrice > 0 ? targetPrice : curPrice,
      currentPrice: curPrice > 0 ? curPrice : targetPrice,
      tolerance: _toDouble(json['tolerance'], 0.20),
      screenshotPath: json['screenshotPath']?.toString() ?? '',
      triggerReason: json['triggerReason']?.toString() ?? '',
      telegramStatus: json['telegramStatus']?.toString() ?? 'SENT',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : (json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
              : (json['triggeredAt'] != null
                  ? DateTime.tryParse(json['triggeredAt'].toString()) ?? DateTime.now()
                  : DateTime.now())),
      isTest: _toBool(json['isTest'], false),
    );
  }
}

class SymbolModel {
  final String symbol;
  final String displayName;
  final String assetType;
  final String exchange;
  final String provider;
  final String tradingViewTicker;
  final int priceDecimals;

  SymbolModel({
    required this.symbol,
    required this.displayName,
    required this.assetType,
    required this.exchange,
    required this.provider,
    required this.tradingViewTicker,
    this.priceDecimals = 2,
  });

  factory SymbolModel.fromJson(Map<String, dynamic> json) {
    return SymbolModel(
      symbol: json['symbol']?.toString() ?? 'XAUUSD',
      displayName: json['displayName']?.toString() ?? 'Gold / USD',
      assetType: json['assetType']?.toString() ?? 'COMMODITY',
      exchange: json['exchange']?.toString() ?? 'OANDA',
      provider: json['provider']?.toString() ?? 'TradingView',
      tradingViewTicker: json['tradingViewTicker']?.toString() ?? 'OANDA:XAUUSD',
      priceDecimals: _toInt(json['priceDecimals'], 2),
    );
  }
}

class PivotStateModel {
  final String symbol;
  final String pivotType;
  final String pivotTimeframe;
  final double high;
  final double low;
  final double close;
  final double p;
  final double r1;
  final double r2;
  final double r3;
  final double s1;
  final double s2;
  final double s3;
  final bool isValid;
  final String periodDateStr;
  final DateTime? nextRolloverAt;

  PivotStateModel({
    required this.symbol,
    this.pivotType = 'FIBONACCI',
    this.pivotTimeframe = 'DAILY',
    required this.high,
    required this.low,
    required this.close,
    required this.p,
    required this.r1,
    required this.r2,
    required this.r3,
    required this.s1,
    required this.s2,
    required this.s3,
    this.isValid = true,
    this.periodDateStr = '',
    this.nextRolloverAt,
  });

  factory PivotStateModel.fromJson(Map<String, dynamic> json) {
    return PivotStateModel(
      symbol: json['symbol']?.toString() ?? 'XAUUSD',
      pivotType: json['pivotType']?.toString() ?? 'TRADITIONAL',
      pivotTimeframe: json['pivotTimeframe']?.toString() ?? 'DAILY',
      high: _toDouble(json['high'], 0.0),
      low: _toDouble(json['low'], 0.0),
      close: _toDouble(json['close'], 0.0),
      p: _toDouble(json['p'], 0.0),
      r1: _toDouble(json['r1'], 0.0),
      r2: _toDouble(json['r2'], 0.0),
      r3: _toDouble(json['r3'], 0.0),
      s1: _toDouble(json['s1'], 0.0),
      s2: _toDouble(json['s2'], 0.0),
      s3: _toDouble(json['s3'], 0.0),
      isValid: _toBool(json['isValid'], true),
      periodDateStr: json['periodDateStr']?.toString() ?? '',
      nextRolloverAt: json['nextRolloverAt'] != null
          ? DateTime.tryParse(json['nextRolloverAt'].toString())
          : null,
    );
  }
}
