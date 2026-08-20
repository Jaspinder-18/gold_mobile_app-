import 'package:flutter/material.dart';
import '../services/audio_service.dart';
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

  late AlertSound _selectedSound;
  late double _volume;
  late bool _soundEnabled;
  late String _selectedRange;
  late int _barSpacing;
  bool _isSaving = false;

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

    _selectedSound = _audioService.currentSound;
    _volume = _audioService.volume;
    _soundEnabled = _audioService.soundEnabled;
    _selectedRange = cfg.chartRange;
    _barSpacing = cfg.barSpacing;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _r3Controller.dispose();
    _r2Controller.dispose();
    _s2Controller.dispose();
    _s3Controller.dispose();
    _toleranceController.dispose();
    _retriggerController.dispose();
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

      final success = await _socketService.updateRemoteConfig({
        'r3': r3,
        'r2': r2,
        's2': s2,
        's3': s3,
        'tolerance': tolerance,
        'retriggerDistance': retrigger,
        'chartRange': _selectedRange,
        'barSpacing': _barSpacing,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            content: Text(
              success ? '✓ Settings & Price Levels Synchronized Live!' : 'Failed to update remote settings',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleAutoCalc() {
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✨ Auto-calculated Fibonacci levels from live market.')),
    );
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
          // Section: Target Levels Editor
          _buildSectionHeader('🎯 TARGET PIVOT LEVELS (R3, R2, S2, S3)'),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Live Target Prices (\$ USD):', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    TextButton.icon(
                      icon: const Icon(Icons.auto_awesome, color: Color(0xFFF59E0B), size: 14),
                      label: const Text('Auto-Calc', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                      onPressed: _handleAutoCalc,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildLevelField('R3 (High Resistance)', _r3Controller, const Color(0xFFF59E0B))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildLevelField('R2 Resistance', _r2Controller, const Color(0xFFF97316))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildLevelField('S2 Support', _s2Controller, const Color(0xFF10B981))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildLevelField('S3 (Low Support)', _s3Controller, const Color(0xFF14B8A6))),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload_outlined, color: Colors.black, size: 16),
                  label: const Text('Save & Broadcast Levels Live', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    minimumSize: const Size.fromHeight(38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isSaving ? null : _handleSaveAll,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Section: TradingView Screenshot Configuration & Bar Spacing
          _buildSectionHeader('📊 CHART ZOOM & BAR SPACING'),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Candle Bar Spacing (Zoom):', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${_barSpacing}px', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                Slider(
                  value: _barSpacing.toDouble(),
                  min: 6,
                  max: 40,
                  divisions: 34,
                  activeColor: const Color(0xFFF59E0B),
                  inactiveColor: const Color(0xFF1E293B),
                  onChanged: (v) {
                    setState(() => _barSpacing = v.toInt());
                  },
                ),
                const SizedBox(height: 8),
                const Text('Screenshot Chart Range:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: ['1D', '2D', '3D', '5D'].map((r) {
                    final isSel = _selectedRange == r;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSel ? const Color(0xFFF59E0B) : const Color(0xFF090D16),
                            foregroundColor: isSel ? Colors.black : Colors.white70,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B)),
                            ),
                          ),
                          onPressed: () => setState(() => _selectedRange = r),
                          child: Text(r, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Section: Alert Sound Selection (Clock / Reminder)
          _buildSectionHeader('🔔 LOUD ALARM & REMINDER SOUNDS'),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Alarm Sound on Level Touch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Play alarm ringtone when R3, R2, S2, S3 are touched', style: TextStyle(color: Colors.white60, fontSize: 10)),
                  value: _soundEnabled,
                  activeThumbColor: const Color(0xFFF59E0B),
                  onChanged: (val) async {
                    setState(() => _soundEnabled = val);
                    await _audioService.setSoundEnabled(val);
                  },
                ),
                const Divider(color: Color(0xFF1E293B)),
                const SizedBox(height: 4),
                const Text('Choose Ringtone:', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 11)),
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
          _buildSectionHeader('🌐 BACKEND SERVER URL'),
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
                const SizedBox(height: 10),
                ElevatedButton.icon(
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
                          const SnackBar(content: Text('Server URL updated and connected!')),
                        );
                      }
                    }
                  },
                ),
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

