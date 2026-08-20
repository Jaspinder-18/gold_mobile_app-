class MarketTick {
  final String symbol;
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
    final p = (json['price'] as num?)?.toDouble() ?? 4356.40;
    return MarketTick(
      symbol: json['symbol'] ?? 'XAUUSD',
      price: p,
      bid: (json['bid'] as num?)?.toDouble() ?? (p - 0.25),
      ask: (json['ask'] as num?)?.toDouble() ?? (p + 0.25),
      high: (json['high'] as num?)?.toDouble() ?? (json['high24h'] as num?)?.toDouble() ?? 4370.00,
      low: (json['low'] as num?)?.toDouble() ?? (json['low24h'] as num?)?.toDouble() ?? 4340.00,
      open: (json['open'] as num?)?.toDouble() ?? 4350.00,
      change: (json['change'] as num?)?.toDouble() ?? 0.0,
      changePercent: (json['changePercent'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
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

  PivotConfig({
    this.r3 = 4657.02,
    this.r2 = 4580.75,
    this.s2 = 4333.97,
    this.s3 = 4257.70,
    this.tolerance = 0.20,
    this.retriggerDistance = 1.00,
    this.chartTimeframe = '15',
    this.chartRange = '1D',
    this.barSpacing = 22,
    this.telegramAlertsEnabled = true,
    this.autoCalculatePivot = false,
  });

  factory PivotConfig.fromJson(Map<String, dynamic> json) {
    return PivotConfig(
      r3: (json['r3'] as num?)?.toDouble() ?? 4473.76,
      r2: (json['r2'] as num?)?.toDouble() ?? 4432.84,
      s2: (json['s2'] as num?)?.toDouble() ?? 4300.45,
      s3: (json['s3'] as num?)?.toDouble() ?? 4259.54,
      tolerance: (json['tolerance'] as num?)?.toDouble() ?? 0.20,
      retriggerDistance: (json['retriggerDistance'] as num?)?.toDouble() ?? 1.00,
      chartTimeframe: json['chartTimeframe']?.toString() ?? '15',
      chartRange: json['chartRange']?.toString() ?? '1D',
      barSpacing: (json['barSpacing'] as num?)?.toInt() ?? 22,
      telegramAlertsEnabled: json['telegramAlertsEnabled'] ?? true,
      autoCalculatePivot: json['autoCalculatePivot'] ?? false,
    );
  }
}

class AlertEvent {
  final String id;
  final String symbol;
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
        ? Map<String, dynamic>.from(rawJson['event'])
        : rawJson;

    return AlertEvent(
      id: (json['_id'] ?? json['id'] ?? 'evt_${DateTime.now().millisecondsSinceEpoch}').toString(),
      symbol: json['symbol']?.toString() ?? 'XAUUSD',
      level: json['level']?.toString() ?? 'R2',
      levelPrice: (json['levelPrice'] as num?)?.toDouble() ?? 4432.84,
      currentPrice: (json['currentPrice'] as num?)?.toDouble() ?? 4432.84,
      tolerance: (json['tolerance'] as num?)?.toDouble() ?? 0.20,
      screenshotPath: json['screenshotPath']?.toString() ?? '',
      triggerReason: json['triggerReason']?.toString() ?? '',
      telegramStatus: json['telegramStatus']?.toString() ?? 'SENT',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : (json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
              : DateTime.now()),
      isTest: json['isTest'] ?? false,
    );
  }
}
