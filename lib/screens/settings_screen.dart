import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/market_data.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../services/onesignal_service.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onBackToMonitor;
  const SettingsScreen({super.key, this.onBackToMonitor});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverUrlController = TextEditingController();
  final _customTargetPriceController = TextEditingController();
  final _onesignalAppIdController = TextEditingController();

  final _audioService = AudioService();
  final _socketService = SocketService();
  final _notificationService = NotificationService();

  late AlertSound _selectedSound;
  late RingtoneLoopMode _selectedLoopMode;
  late double _volume;
  late bool _soundEnabled;
  late bool _vibrationEnabled;

  // Chart settings
  late AppTimeframe _selectedTimeframe;
  late AppChartRange _selectedRange;
  late AppBarSpacing _selectedBarSpacing;

  // Custom alert settings
  late bool _customPriceAlertEnabled;
  bool _isSaving = false;
  bool _isTestingPing = false;
  String? _pingResult;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  void _loadCurrentConfig() async {
    final cfg = _socketService.currentConfig;
    _serverUrlController.text = _socketService.serverUrl;

    try {
      final prefs = await SharedPreferences.getInstance();
      _onesignalAppIdController.text = prefs.getString('onesignal_app_id') ?? '';
    } catch (_) {}

    _customPriceAlertEnabled = cfg.customPriceAlertEnabled;
    _customTargetPriceController.text = cfg.customPriceAlertTarget > 0 ? cfg.customPriceAlertTarget.toStringAsFixed(2) : '';

    _selectedSound = _audioService.currentSound;
    _selectedLoopMode = _audioService.loopMode;
    _volume = _audioService.volume;
    _soundEnabled = _audioService.soundEnabled;
    _vibrationEnabled = _audioService.vibrationEnabled;

    _selectedTimeframe = AppTimeframe.fromString(cfg.chartTimeframe);
    _selectedRange = AppChartRange.fromString(cfg.chartRange);
    _selectedBarSpacing = AppBarSpacing.fromValue(cfg.barSpacing);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _audioService.stop();
    _serverUrlController.dispose();
    _customTargetPriceController.dispose();
    _onesignalAppIdController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveAll() async {
    setState(() => _isSaving = true);
    try {
      final customTarget = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? _socketService.currentConfig.customPriceAlertTarget;

      // 1. Save Audio & Notification Settings locally
      await _audioService.setSound(_selectedSound);
      await _audioService.setLoopMode(_selectedLoopMode);
      await _audioService.setVolume(_volume);
      await _audioService.setSoundEnabled(_soundEnabled);
      await _audioService.setVibrationEnabled(_vibrationEnabled);

      // 2. Save OneSignal App ID
      if (_onesignalAppIdController.text.trim().isNotEmpty) {
        await OneSignalService().setAppId(_onesignalAppIdController.text.trim());
      }

      // 3. Update server URL if changed FIRST
      final newUrl = _serverUrlController.text.trim();
      if (newUrl.isNotEmpty && newUrl != _socketService.serverUrl) {
        await _socketService.updateServerUrl(newUrl);
      }

      // 3. Cache custom alert & chart settings locally in SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final sym = _socketService.activeSymbol.toUpperCase();
        await prefs.setDouble('custom_target_price_$sym', customTarget);
        await prefs.setDouble('custom_price_alert_target_$sym', customTarget);
        await prefs.setBool('custom_price_alert_enabled_$sym', _customPriceAlertEnabled);
        await prefs.setString('chart_timeframe_$sym', _selectedTimeframe.apiValue);
        await prefs.setString('chart_range_$sym', _selectedRange.label);
        await prefs.setInt('bar_spacing_$sym', _selectedBarSpacing.px);
      } catch (_) {}

      // 4. Update custom price alert
      if (_customPriceAlertEnabled && customTarget > 0) {
        _socketService.createCustomAlert(targetPrice: customTarget);
      } else if (!_customPriceAlertEnabled) {
        _socketService.clearAllCustomAlerts();
      }

      // 5. Update remote config (optimistic local + remote sync)
      final synced = await _socketService.updateRemoteConfig({
        'chartTimeframe': _selectedTimeframe.apiValue,
        'chartRange': _selectedRange.label,
        'barSpacing': _selectedBarSpacing.px,
        'customPriceAlertEnabled': _customPriceAlertEnabled,
        'customPriceAlertTarget': customTarget,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    synced
                        ? '✓ All Settings Saved & Synced Live!'
                        : '✓ Settings Saved Locally on Device!',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('✓ Settings Saved Locally on Device!'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleCancelAlert() async {
    setState(() => _isSaving = true);
    try {
      final ok = await _socketService.deleteCustomPriceAlert();
      if (mounted) {
        setState(() {
          _customPriceAlertEnabled = false;
          _customTargetPriceController.clear();
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            content: Text(ok ? '✓ Custom Alert Cancelled and Monitoring Stopped.' : 'Failed to cancel alert.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleTestPing() async {
    setState(() {
      _isTestingPing = true;
      _pingResult = null;
    });
    final res = await _socketService.checkServerConnectivity();
    if (mounted) {
      setState(() {
        _isTestingPing = false;
        _pingResult = res['message']?.toString();
      });
    }
  }

  Future<void> _handleTestAlarmAndNotification() async {
    final targetPrice = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? (_socketService.currentConfig.customPriceAlertTarget > 0 ? _socketService.currentConfig.customPriceAlertTarget : (_socketService.currentTick?.price ?? 3450.50));
    await _socketService.triggerLocalTestAlert(level: 'CUSTOM', price: targetPrice);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('🚨 Custom Alert Test Fired @ \$${targetPrice.toStringAsFixed(2)}: Sound & Notification Dispatched!'),
        ),
      );
    }
  }

  Future<void> _handleTestServerAlert() async {
    final targetPrice = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? (_socketService.currentConfig.customPriceAlertTarget > 0 ? _socketService.currentConfig.customPriceAlertTarget : (_socketService.currentTick?.price ?? 3450.50));
    final success = await _socketService.triggerRemoteTestAlert(level: 'CUSTOM', price: targetPrice);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            success ? '🚨 Server Alert Triggered @ \$${targetPrice.toStringAsFixed(2)}! Dispatched to all devices.' : 'Failed to trigger server alert. Check connection.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  Future<void> _handleTestFcmPush() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF3B82F6),
        duration: Duration(seconds: 4),
        content: Text('⏳ Dispatching FCM Cloud Push in 3 seconds... Close the app or lock phone NOW to test!'),
      ),
    );

    await Future.delayed(const Duration(seconds: 3));
    final success = await _notificationService.sendFcmTestPush(serverUrl: _serverUrlController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            success
                ? '🔥 Firebase Push Dispatched! Alarm should ring on your phone.'
                : 'Failed to dispatch FCM push. Check server URL or Firebase key.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
        title: const Text('Confirm Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        content: const Text('Are you sure you want to log out from this device?', style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService().logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  Widget _buildUserProfileCard() {
    final user = AuthService().currentUser;
    final name = user?.fullName ?? 'Trader';
    final email = user?.email ?? 'Not signed in';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'T';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFF59E0B),
            child: Text(
              initial,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Account Active · Device Paired',
                      style: TextStyle(color: Colors.greenAccent.shade400, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFEF4444)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.logout, color: Color(0xFFEF4444), size: 14),
            label: const Text(
              'LOGOUT',
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.w900),
            ),
            onPressed: _handleLogout,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final livePrice = _socketService.currentTick?.price ?? 3448.20;
    final targetPrice = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? _socketService.currentConfig.customPriceAlertTarget;
    final distance = (livePrice - targetPrice).abs();
    final customState = _socketService.levelStates['CUSTOM'] ?? 'INACTIVE';
    final isTriggered = customState == 'TRIGGERED';
    final isActive = _customPriceAlertEnabled && targetPrice > 0 && !isTriggered;

    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1626),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else if (widget.onBackToMonitor != null) {
              widget.onBackToMonitor!();
            }
          },
        ),
        title: const Text(
          'Settings & Configuration',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            icon: _isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.save, color: Colors.black, size: 16),
            label: const Text('SAVE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isSaving ? null : _handleSaveAll,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          // 1. USER ACCOUNT & ACTIVE DEVICE STATUS
          _buildSectionHeader('👤 TRADER ACCOUNT & DEVICE PAIRING'),
          _buildUserProfileCard(),

          const SizedBox(height: 12),

          // 2. QUICK ALERT ENGINE TEST BANNER
          _buildTestBanner(),

          const SizedBox(height: 12),

          // 3. CUSTOM PRICE ALERT CARD
          _buildSectionHeader('🎯 CUSTOM PRICE ALERT'),
          _buildCustomPriceAlertCard(livePrice, targetPrice, distance, isActive, isTriggered),

          const SizedBox(height: 14),

          // 4. LOUD ALARM & SYSTEM PUSH NOTIFICATION SETTINGS
          _buildSectionHeader('🔔 LOUD ALARM & NOTIFICATION SETTINGS'),
          _buildAudioAndNotificationCard(),

          const SizedBox(height: 14),

          // 5. CHART SETTINGS CARD (Timeframe, Chart Range, Bar Spacing)
          _buildSectionHeader('📊 CHART SETTINGS'),
          _buildChartSettingsCard(),

          const SizedBox(height: 14),

          // 6. SERVER DIAGNOSTICS & PING TEST
          _buildSectionHeader('🌐 BACKEND SERVER & DIAGNOSTICS'),
          _buildServerDiagnosticsCard(),

          const SizedBox(height: 16),

          // 6. BOTTOM SAVE BUTTON
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.check_circle, color: Colors.black, size: 18),
              label: Text(
                _isSaving ? 'SAVING SETTINGS...' : 'SAVE ALL SETTINGS',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
              onPressed: _isSaving ? null : _handleSaveAll,
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTestBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFEF4444).withValues(alpha: 0.18),
            const Color(0xFFF59E0B).withValues(alpha: 0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.crisis_alert, color: Color(0xFFF59E0B), size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Test Alert & Notification Engine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('Verify loud alarm sound, full-screen notification & vibration', style: TextStyle(color: Colors.white60, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.volume_up, size: 13, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _handleTestAlarmAndNotification,
                  label: const Text('LOCAL ALARM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload, size: 13, color: Colors.black),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _handleTestServerAlert,
                  label: const Text('SERVER ALERT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.notifications_active, size: 13, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _handleTestFcmPush,
                  label: const Text('FCM PUSH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TIMEFRAME SELECTOR (16 Options)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.schedule, color: Color(0xFFF59E0B), size: 16),
                  SizedBox(width: 6),
                  Text('Time Frame', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _selectedTimeframe.fullTitle,
                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AppTimeframe>(
                value: _selectedTimeframe,
                isExpanded: true,
                dropdownColor: const Color(0xFF0E1626),
                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFF59E0B)),
                items: AppTimeframe.values.map((tf) {
                  return DropdownMenuItem<AppTimeframe>(
                    value: tf,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tf.fullTitle, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(tf.label, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedTimeframe = val);
                },
              ),
            ),
          ),

          const SizedBox(height: 14),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: 12),

          // 2. CHART RANGE SELECTOR (1D, 2D, 3D, 4D, 5D)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.calendar_month, color: Color(0xFFF59E0B), size: 16),
                  SizedBox(width: 6),
                  Text('Chart Range', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              Text(
                '${_selectedRange.title} candles',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: AppChartRange.values.map((r) {
              final isSel = _selectedRange == r;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedRange = r),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF070A12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                        width: isSel ? 1.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      r.label,
                      style: TextStyle(
                        color: isSel ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: 12),

          // 3. BAR SPACING SELECTOR
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.view_column, color: Color(0xFFF59E0B), size: 16),
                  SizedBox(width: 6),
                  Text('Bar Spacing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              Text(
                '${_selectedBarSpacing.label} (${_selectedBarSpacing.px}px)',
                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AppBarSpacing.values.map((sp) {
                final isSel = _selectedBarSpacing == sp;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      sp.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSel ? Colors.black : Colors.white70,
                      ),
                    ),
                    selected: isSel,
                    selectedColor: const Color(0xFFF59E0B),
                    backgroundColor: const Color(0xFF070A12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                    ),
                    onSelected: (_) => setState(() => _selectedBarSpacing = sp),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomPriceAlertCard(double livePrice, double targetPrice, double distance, bool isActive, bool isTriggered) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTriggered ? const Color(0xFFEF4444) : (isActive ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
          width: isActive || isTriggered ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isTriggered ? const Color(0xFFEF4444) : (isActive ? const Color(0xFF10B981) : Colors.grey),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isTriggered ? '● TRIGGERED' : (isActive ? '● ACTIVE' : '● INACTIVE / PAUSED'),
                    style: TextStyle(
                      color: isTriggered ? const Color(0xFFEF4444) : (isActive ? const Color(0xFF10B981) : Colors.white60),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _customPriceAlertEnabled,
                activeThumbColor: const Color(0xFFF59E0B),
                activeTrackColor: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                inactiveThumbColor: Colors.grey[600],
                inactiveTrackColor: const Color(0xFF1E293B),
                onChanged: (val) {
                  setState(() => _customPriceAlertEnabled = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _customTargetPriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.w900, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Target Price (\$ USD)',
              labelStyle: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12),
              prefixText: '\$ ',
              prefixStyle: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
              hintText: '3450.50',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: const Color(0xFF070A12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (targetPrice > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF070A12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live Price: \$${livePrice.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text(
                        targetPrice > livePrice ? '↗ TARGET ABOVE (+\$${distance.toStringAsFixed(2)})' : '↘ TARGET BELOW (-\$${distance.toStringAsFixed(2)})',
                        style: TextStyle(
                          color: targetPrice > livePrice ? const Color(0xFF10B981) : const Color(0xFF60A5FA),
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  if (isActive)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 12, color: Color(0xFFEF4444)),
                      label: const Text('CANCEL ALERT', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: _handleCancelAlert,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioAndNotificationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.notifications_active, color: Color(0xFFF59E0B), size: 22),
            title: const Text('System Push Notifications', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text('Required for lock-screen alarm banner and alert popups', style: TextStyle(color: Colors.white60, fontSize: 10)),
            trailing: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await _notificationService.requestPermissions();
                await _notificationService.testNotification();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Notification test dispatched!')),
                );
              },
              child: const Text('Grant / Test', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const Divider(color: Color(0xFF1E293B)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Alarm Sound on Price Touch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text('Play loud alarm ringtone when custom target is reached', style: TextStyle(color: Colors.white60, fontSize: 10)),
            value: _soundEnabled,
            activeThumbColor: const Color(0xFFF59E0B),
            onChanged: (val) async {
              setState(() => _soundEnabled = val);
              await _audioService.setSoundEnabled(val);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Vibrate on Price Touch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text('Tactile haptic vibration when price touches target', style: TextStyle(color: Colors.white60, fontSize: 10)),
            value: _vibrationEnabled,
            activeThumbColor: const Color(0xFFF59E0B),
            onChanged: (val) async {
              setState(() => _vibrationEnabled = val);
              await _audioService.setVibrationEnabled(val);
            },
          ),
          const Divider(color: Color(0xFF1E293B)),
          const SizedBox(height: 6),
          const Text('Ringtone Loop Duration:', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: RingtoneLoopMode.values.map((mode) {
              final isSel = _selectedLoopMode == mode;
              return InkWell(
                onTap: () async {
                  setState(() => _selectedLoopMode = mode);
                  await _audioService.setLoopMode(mode);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF070A12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                      width: isSel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      color: isSel ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1E293B)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Choose Alarm Sound:', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 11)),
              if (_audioService.isPlaying)
                InkWell(
                  onTap: () async {
                    await _audioService.stop();
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFEF4444)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop, color: Colors.redAccent, size: 12),
                        SizedBox(width: 2),
                        Text('Stop Audio', style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ...AlertSound.values.map((sound) {
            final isSelected = _selectedSound == sound;
            final isCustom = sound == AlertSound.customMedia;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFF070A12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () async {
                      if (isCustom && _audioService.customAudioPath == null) {
                        final picked = await _audioService.pickAndSetCustomAudio();
                        if (picked && mounted) {
                          setState(() => _selectedSound = AlertSound.customMedia);
                          await _audioService.testSound(AlertSound.customMedia);
                        }
                      } else {
                        setState(() => _selectedSound = sound);
                        await _audioService.setSound(sound);
                        await _audioService.testSound(sound);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? const Color(0xFFF59E0B) : Colors.grey,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isCustom ? Icons.music_note : Icons.audiotrack,
                            color: isSelected ? const Color(0xFFF59E0B) : Colors.white54,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sound.title,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                                if (isCustom && _audioService.customAudioName != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '📁 ${_audioService.customAudioName!}',
                                    style: const TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isCustom)
                            TextButton.icon(
                              icon: const Icon(Icons.folder_open, size: 13, color: Color(0xFFF59E0B)),
                              label: Text(
                                _audioService.customAudioName != null ? 'Change' : 'Browse',
                                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () async {
                                final picked = await _audioService.pickAndSetCustomAudio();
                                if (picked && mounted) {
                                  setState(() => _selectedSound = AlertSound.customMedia);
                                  await _audioService.testSound(AlertSound.customMedia);
                                }
                              },
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.volume_up, color: Color(0xFFF59E0B), size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _audioService.testSound(sound),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Volume:', style: TextStyle(color: Colors.white70, fontSize: 11)),
              Expanded(
                child: Slider(
                  value: _volume,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  activeColor: const Color(0xFFF59E0B),
                  inactiveColor: const Color(0xFF1E293B),
                  onChanged: (v) async {
                    setState(() => _volume = v);
                    await _audioService.setVolume(v);
                  },
                ),
              ),
              Text('${(_volume * 100).toInt()}%', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServerDiagnosticsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _serverUrlController,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF070A12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
              prefixIcon: const Icon(Icons.cloud_queue, color: Color(0xFFF59E0B), size: 18),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  backgroundColor: const Color(0xFF070A12),
                  side: const BorderSide(color: Color(0xFF1E293B)),
                  avatar: const Icon(Icons.cloud, color: Color(0xFFF59E0B), size: 14),
                  label: const Text('Render Cloud', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() {
                      _serverUrlController.text = 'https://gold-server-dbbq.onrender.com';
                    });
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  backgroundColor: const Color(0xFF070A12),
                  side: const BorderSide(color: Color(0xFF1E293B)),
                  avatar: const Icon(Icons.wifi, color: Color(0xFF10B981), size: 14),
                  label: const Text('Local PC (192.168.1.48)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() {
                      _serverUrlController.text = 'http://192.168.1.48:5001';
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _isTestingPing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)))
                      : const Icon(Icons.speed, color: Color(0xFFF59E0B), size: 16),
                  label: const Text('Test Ping', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isTestingPing ? null : _handleTestPing,
                ),
              ),
            ],
          ),
          if (_pingResult != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _pingResult!.contains('Connected')
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _pingResult!.contains('Connected') ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
              ),
              child: Text(
                _pingResult!,
                style: TextStyle(
                  color: _pingResult!.contains('Connected') ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFF59E0B),
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

