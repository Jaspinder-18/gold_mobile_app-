import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../services/socket_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverUrlController = TextEditingController();
  final _r3Controller = TextEditingController();
  final _r2Controller = TextEditingController();
  final _s2Controller = TextEditingController();
  final _s3Controller = TextEditingController();
  final _toleranceController = TextEditingController();
  final _retriggerController = TextEditingController();

  final _audioService = AudioService();
  final _socketService = SocketService();
  final _notificationService = NotificationService();

  late AlertSound _selectedSound;
  late RingtoneLoopMode _selectedLoopMode;
  late double _volume;
  late bool _soundEnabled;
  late bool _vibrationEnabled;
  late String _selectedRange;
  late int _barSpacing;
  late int _autoCalcIntervalMinutes;
  late bool _customPriceAlertEnabled;
  final TextEditingController _customTargetPriceController = TextEditingController();
  bool _isSaving = false;
  bool _isTestingPing = false;
  String? _pingResult;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  void _loadCurrentConfig() {
    final cfg = _socketService.currentConfig;
    _serverUrlController.text = _socketService.serverUrl;
    _r3Controller.text = cfg.r3.toStringAsFixed(2);
    _r2Controller.text = cfg.r2.toStringAsFixed(2);
    _s2Controller.text = cfg.s2.toStringAsFixed(2);
    _s3Controller.text = cfg.s3.toStringAsFixed(2);
    _toleranceController.text = cfg.tolerance.toStringAsFixed(2);
    _retriggerController.text = cfg.retriggerDistance.toStringAsFixed(2);

    _customPriceAlertEnabled = cfg.customPriceAlertEnabled;
    _customTargetPriceController.text = cfg.customPriceAlertTarget > 0 ? cfg.customPriceAlertTarget.toStringAsFixed(2) : '';

    _selectedSound = _audioService.currentSound;
    _selectedLoopMode = _audioService.loopMode;
    _volume = _audioService.volume;
    _soundEnabled = _audioService.soundEnabled;
    _vibrationEnabled = _audioService.vibrationEnabled;
    _selectedRange = cfg.chartRange;
    _barSpacing = cfg.barSpacing;
    _autoCalcIntervalMinutes = cfg.autoCalcIntervalMinutes;
  }

  @override
  void dispose() {
    _audioService.stop();
    _serverUrlController.dispose();
    _r3Controller.dispose();
    _r2Controller.dispose();
    _s2Controller.dispose();
    _s3Controller.dispose();
    _toleranceController.dispose();
    _retriggerController.dispose();
    _customTargetPriceController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveAll() async {
    setState(() => _isSaving = true);
    try {
      final r3 = double.tryParse(_r3Controller.text) ?? _socketService.currentConfig.r3;
      final r2 = double.tryParse(_r2Controller.text) ?? _socketService.currentConfig.r2;
      final s2 = double.tryParse(_s2Controller.text) ?? _socketService.currentConfig.s2;
      final s3 = double.tryParse(_s3Controller.text) ?? _socketService.currentConfig.s3;
      final tolerance = double.tryParse(_toleranceController.text) ?? _socketService.currentConfig.tolerance;
      final retrigger = double.tryParse(_retriggerController.text) ?? _socketService.currentConfig.retriggerDistance;
      final customTarget = double.tryParse(_customTargetPriceController.text.replaceAll(',', '')) ?? _socketService.currentConfig.customPriceAlertTarget;

      // Save Audio & Notification Settings
      await _audioService.setSound(_selectedSound);
      await _audioService.setLoopMode(_selectedLoopMode);
      await _audioService.setVolume(_volume);
      await _audioService.setSoundEnabled(_soundEnabled);
      await _audioService.setVibrationEnabled(_vibrationEnabled);

      final success = await _socketService.updateRemoteConfig({
        'r3': r3,
        'r2': r2,
        's2': s2,
        's3': s3,
        'tolerance': tolerance,
        'retriggerDistance': retrigger,
        'chartRange': _selectedRange,
        'barSpacing': _barSpacing,
        'autoCalculatePivot': true,
        'autoCalcIntervalMinutes': _autoCalcIntervalMinutes,
        'customPriceAlertEnabled': _customPriceAlertEnabled,
        'customPriceAlertTarget': customTarget,
      });

      // Cache custom alert locally
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('custom_target_price_${_socketService.activeSymbol.toUpperCase()}', customTarget);
        await prefs.setBool('custom_price_alert_enabled_${_socketService.activeSymbol.toUpperCase()}', _customPriceAlertEnabled);
      } catch (_) {}

      // Update server URL if changed
      final newUrl = _serverUrlController.text.trim();
      if (newUrl.isNotEmpty && newUrl != _socketService.serverUrl) {
        await _socketService.updateServerUrl(newUrl);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            content: Text(
              success ? '✓ All Settings, Sounds & Price Levels Synchronized Live!' : 'Failed to update remote settings',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleAutoCalc() async {
    setState(() => _isSaving = true);
    final ok = await _socketService.autoCalculatePivots();
    setState(() => _isSaving = false);
    if (ok) {
      final cfg = _socketService.currentConfig;
      setState(() {
        _r3Controller.text = cfg.r3.toStringAsFixed(2);
        _r2Controller.text = cfg.r2.toStringAsFixed(2);
        _s2Controller.text = cfg.s2.toStringAsFixed(2);
        _s3Controller.text = cfg.s3.toStringAsFixed(2);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('✨ Authoritative Pivot Levels auto-calculated & replaced!'),
          ),
        );
      }
    } else {
      // Local fallback
      final tick = _socketService.currentTick;
      final price = tick?.price ?? 4481.17;
      final h = (tick != null && tick.high > price) ? tick.high : (price + 32.0);
      final l = (tick != null && tick.low < price) ? tick.low : (price - 32.0);
      final c = price;
      final range = h - l;
      final p = (h + l + c) / 3;

      setState(() {
        _r3Controller.text = (p + 1.000 * range).toStringAsFixed(2);
        _r2Controller.text = (p + 0.618 * range).toStringAsFixed(2);
        _s2Controller.text = (p - 0.618 * range).toStringAsFixed(2);
        _s3Controller.text = (p - 1.000 * range).toStringAsFixed(2);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✨ Calculated Fibonacci levels from live market.')),
        );
      }
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
    await _socketService.triggerLocalTestAlert(level: 'R2', price: _socketService.currentTick?.price ?? 4580.75);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF10B981),
          content: Text('🚨 Test Alert Fired: Sound & System Notification Dispatched!'),
        ),
      );
    }
  }

  Future<void> _handleTestServerAlert() async {
    final success = await _socketService.triggerRemoteTestAlert(level: 'R2');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            success ? '🚨 Server Alert Triggered! Incoming WebSocket Alert Dispatched.' : 'Failed to trigger server alert. Check server connection.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings & Level Engine',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)))
                : const Icon(Icons.save, color: Color(0xFFF59E0B)),
            onPressed: _isSaving ? null : _handleSaveAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          // Quick Test Banner
          Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                    Icon(Icons.crisis_alert, color: Color(0xFFF59E0B), size: 24),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Test Alert & Notification Engine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Verify sound, vibration, and push notifications', style: TextStyle(color: Colors.white60, fontSize: 10)),
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
                        icon: const Icon(Icons.volume_up, size: 14, color: Colors.white),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _handleTestAlarmAndNotification,
                        label: const Text('LOCAL TEST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.cloud_upload, size: 14, color: Colors.black),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _handleTestServerAlert,
                        label: const Text('SERVER TEST', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Section: Custom Specific Price Alert
          _buildSectionHeader('🎯 CUSTOM SPECIFIC PRICE ALERT (ON / OFF)'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _customPriceAlertEnabled ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                width: _customPriceAlertEnabled ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enable Custom Price Alarm',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            _customPriceAlertEnabled ? 'Active: Alarm rings when market touches target' : 'Paused / Off',
                            style: TextStyle(
                              color: _customPriceAlertEnabled ? const Color(0xFFFBBF24) : Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _customPriceAlertEnabled,
                      activeColor: const Color(0xFFF59E0B),
                      activeTrackColor: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      inactiveThumbColor: Colors.grey[600],
                      inactiveTrackColor: const Color(0xFF1E293B),
                      onChanged: (val) {
                        setState(() => _customPriceAlertEnabled = val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _customTargetPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Custom Target Price (\$ USD)',
                    labelStyle: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12),
                    hintText: 'e.g. 4410.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF070A12),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Section: Alert Sound Selection (Clock / Reminder)
          _buildSectionHeader('🔔 LOUD ALARM & RINGTONE SETTINGS'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Notification Permission Row
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.notifications_active, color: Color(0xFFF59E0B), size: 20),
                  title: const Text('System Push Notifications', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Required for lock-screen alarm banner', style: TextStyle(color: Colors.white60, fontSize: 10)),
                  trailing: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: () async {
                      await _notificationService.requestPermissions();
                      await _notificationService.testNotification();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Notification permission requested and test dispatched!')),
                        );
                      }
                    },
                    child: const Text('Grant / Test', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Divider(color: Color(0xFF1E293B)),

                // 1. Alarm Sound Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Alarm Sound on Level Touch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Play loud alarm ringtone when R3, R2, S2, S3 are touched', style: TextStyle(color: Colors.white60, fontSize: 10)),
                  value: _soundEnabled,
                  activeThumbColor: const Color(0xFFF59E0B),
                  onChanged: (val) async {
                    setState(() => _soundEnabled = val);
                    await _audioService.setSoundEnabled(val);
                  },
                ),

                // 2. Vibration Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Vibrate on Level Touch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Tactile haptic vibration when price touches target levels', style: TextStyle(color: Colors.white60, fontSize: 10)),
                  value: _vibrationEnabled,
                  activeThumbColor: const Color(0xFFF59E0B),
                  onChanged: (val) async {
                    setState(() => _vibrationEnabled = val);
                    await _audioService.setVibrationEnabled(val);
                  },
                ),

                const Divider(color: Color(0xFF1E293B)),
                const SizedBox(height: 6),

                // 3. Ringtone Loop Duration Selector (1 min, 5 min, etc.)
                const Text('Ringtone Loop Duration:', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 11)),
                const SizedBox(height: 3),
                const Text('How long the alarm rings before automatically silencing', style: TextStyle(color: Colors.white38, fontSize: 9)),
                const SizedBox(height: 8),

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
                          color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF090D16),
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

                // 4. Choose Ringtone
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
                        borderRadius: BorderRadius.circular(4),
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
                  return InkWell(
                    onTap: () async {
                      setState(() => _selectedSound = sound);
                      await _audioService.setSound(sound);
                      await _audioService.testSound(sound);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFF090D16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? const Color(0xFFF59E0B) : Colors.grey,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              sound.title,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.volume_up, color: Color(0xFFF59E0B), size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _audioService.testSound(sound),
                            tooltip: 'Test Sound',
                          ),
                        ],
                      ),
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
          ),

          const SizedBox(height: 14),

          // Section: Backend Server URL
          _buildSectionHeader('🌐 BACKEND SERVER URL & DIAGNOSTICS'),
          Container(
            padding: const EdgeInsets.all(12),
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
                    fillColor: const Color(0xFF090D16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                    ),
                    prefixIcon: const Icon(Icons.cloud_queue, color: Color(0xFFF59E0B), size: 18),
                  ),
                ),
                const SizedBox(height: 8),

                // Quick Presets
                const Text('Quick Presets:', style: TextStyle(color: Colors.white60, fontSize: 10)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ActionChip(
                      backgroundColor: const Color(0xFF1E293B),
                      label: const Text('☁️ Cloud (Render)', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10)),
                      onPressed: () {
                        _serverUrlController.text = 'https://gold-server-dbbq.onrender.com';
                      },
                    ),
                    ActionChip(
                      backgroundColor: const Color(0xFF1E293B),
                      label: const Text('📱 Android Emulator', style: TextStyle(color: Color(0xFF10B981), fontSize: 10)),
                      onPressed: () {
                        _serverUrlController.text = 'http://10.0.2.2:5001';
                      },
                    ),
                    ActionChip(
                      backgroundColor: const Color(0xFF1E293B),
                      label: const Text('💻 Localhost Port 5001', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 10)),
                      onPressed: () {
                        _serverUrlController.text = 'http://localhost:5001';
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 10),
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
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.sync, color: Colors.black, size: 16),
                        label: const Text('Save & Reconnect', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          minimumSize: const Size.fromHeight(38),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final newUrl = _serverUrlController.text.trim();
                          if (newUrl.isNotEmpty) {
                            await _socketService.updateServerUrl(newUrl);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Server URL updated and reconnect initiated!')),
                              );
                            }
                          }
                        },
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
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLevelField(String label, TextEditingController controller, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFF090D16),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
          ),
        ),
      ],
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
          fontSize: 10,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

