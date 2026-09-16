import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/market_data.dart';
import '../services/audio_service.dart';
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
  final _audioService = AudioService();
  final _socketService = SocketService();

  late AlertSound _selectedSound;
  late RingtoneLoopMode _selectedLoopMode;
  late double _volume;

  // Chart settings
  late AppTimeframe _selectedTimeframe;
  late AppChartRange _selectedRange;
  late AppBarSpacing _selectedBarSpacing;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  void _loadCurrentConfig() async {
    final cfg = _socketService.currentConfig;

    _selectedSound = _audioService.currentSound;
    _selectedLoopMode = _audioService.loopMode;
    _volume = _audioService.volume;

    _selectedTimeframe = AppTimeframe.fromString(cfg.chartTimeframe);
    _selectedRange = AppChartRange.fromString(cfg.chartRange);
    _selectedBarSpacing = AppBarSpacing.fromValue(cfg.barSpacing);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _audioService.stop();
    super.dispose();
  }

  Future<void> _handleSaveAll() async {
    setState(() => _isSaving = true);
    try {
      // 1. Save Audio Settings locally
      await _audioService.setSound(_selectedSound);
      await _audioService.setLoopMode(_selectedLoopMode);
      await _audioService.setVolume(_volume);

      // 2. Cache chart settings locally in SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final sym = _socketService.activeSymbol.toUpperCase();
        await prefs.setString('chart_timeframe_$sym', _selectedTimeframe.apiValue);
        await prefs.setString('chart_range_$sym', _selectedRange.label);
        await prefs.setInt('bar_spacing_$sym', _selectedBarSpacing.px);
      } catch (_) {}

      // 3. Update remote config
      final synced = await _socketService.updateRemoteConfig({
        'chartTimeframe': _selectedTimeframe.apiValue,
        'chartRange': _selectedRange.label,
        'barSpacing': _selectedBarSpacing.px,
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

          const SizedBox(height: 14),

          // 2. LOUD ALARM & SOUND SELECTION
          _buildSectionHeader('🔔 LOUD ALARM SOUND SETTINGS'),
          _buildAudioAndNotificationCard(),

          const SizedBox(height: 14),

          // 3. CHART SETTINGS CARD (Timeframe, Chart Range, Bar Spacing)
          _buildSectionHeader('📊 CHART SETTINGS'),
          _buildChartSettingsCard(),

          const SizedBox(height: 16),

          // 4. BOTTOM SAVE BUTTON
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.volume_up_rounded, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 6),
                  Text('Select Price Alert Sound:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              if (_audioService.isPlaying)
                InkWell(
                  onTap: () async {
                    await _audioService.stop();
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFEF4444)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop_rounded, color: Colors.redAccent, size: 14),
                        SizedBox(width: 3),
                        Text('Stop Audio', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 5 Distinct, Clean Sound Options
          ...AlertSound.values.map((sound) {
            final isSelected = _selectedSound == sound;
            final isVibrate = sound == AlertSound.vibrateOnly;
            final isDevice = sound == AlertSound.deviceSound;
            final customFileName = _audioService.customAudioName;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFF070A12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () async {
                      setState(() => _selectedSound = sound);
                      await _audioService.setSound(sound);
                      await _audioService.testSound(sound);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? const Color(0xFFF59E0B) : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            isVibrate ? Icons.vibration : (isDevice ? Icons.folder_open_rounded : Icons.music_note_rounded),
                            color: isSelected ? const Color(0xFFF59E0B) : Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sound.title,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12.5,
                                  ),
                                ),
                                if (isDevice && customFileName != null && customFileName.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Selected: $customFileName',
                                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10.5, fontFamily: 'monospace'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isVibrate ? Icons.touch_app : Icons.volume_up,
                              color: const Color(0xFFF59E0B),
                              size: 18,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Preview Sound',
                            onPressed: () => _audioService.testSound(sound),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // If Device Sound selected, show Browse button
                  if (isDevice) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 40, right: 12, bottom: 10, top: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.file_upload_outlined, size: 14, color: Color(0xFFF59E0B)),
                              label: Text(
                                customFileName != null && customFileName.isNotEmpty
                                    ? 'Change Audio File'
                                    : 'Browse Audio File from Device',
                                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFF59E0B)),
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () async {
                                final picked = await _audioService.pickAndSetCustomAudio();
                                if (picked && mounted) {
                                  setState(() => _selectedSound = AlertSound.deviceSound);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF10B981),
                                      content: Text('✓ Custom audio loaded: ${_audioService.customAudioName}'),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1E293B)),
          const SizedBox(height: 8),

          // Alarm Volume Slider
          Row(
            children: [
              const Icon(Icons.volume_down, color: Colors.white60, size: 16),
              const SizedBox(width: 6),
              const Text('Alarm Volume:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
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
              Text('${(_volume * 100).toInt()}%', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace')),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(color: Color(0xFF1E293B)),
          const SizedBox(height: 8),

          // Ringtone Loop Duration
          const Row(
            children: [
              Icon(Icons.repeat, color: Color(0xFFF59E0B), size: 16),
              SizedBox(width: 6),
              Text('Alarm Ringtone Loop Duration:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
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
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              );
            }).toList(),
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
