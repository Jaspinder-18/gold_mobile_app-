import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RingtoneLoopMode {
  playOnce('Play Once (~5s)', 0),
  loop30s('Loop 30s', 30),
  loop1Min('Loop 1 Minute', 60),
  loop2Min('Loop 2 Minutes', 120),
  loop5Min('Loop 5 Minutes', 300),
  loopContinuous('Continuous (Until Dismissed)', -1);

  final String label;
  final int seconds;
  const RingtoneLoopMode(this.label, this.seconds);
}

enum AlertSound {
  alarmClock('Alarm Clock (Loud Digital)', 'alarm_clock.wav'),
  reminderBell('Reminder Bell (Melodic Chime)', 'reminder_bell.wav'),
  radarAlert('Radar Alert (Tactical Ping)', 'radar_alert.wav'),
  cyberSiren('Cyber Siren (Emergency Alarm)', 'cyber_siren.wav');

  final String title;
  final String fileName;
  const AlertSound(this.title, this.fileName);
}

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  AlertSound _currentSound = AlertSound.alarmClock;
  RingtoneLoopMode _loopMode = RingtoneLoopMode.loop1Min;
  double _volume = 1.0;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _isPlaying = false;
  Timer? _stopTimer;

  AlertSound get currentSound => _currentSound;
  RingtoneLoopMode get loopMode => _loopMode;
  double get volume => _volume;
  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get isPlaying => _isPlaying;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final soundName = prefs.getString('alert_sound') ?? AlertSound.alarmClock.name;
    _currentSound = AlertSound.values.firstWhere(
      (s) => s.name == soundName,
      orElse: () => AlertSound.alarmClock,
    );

    final loopModeName = prefs.getString('alert_loop_mode') ?? RingtoneLoopMode.loop1Min.name;
    _loopMode = RingtoneLoopMode.values.firstWhere(
      (m) => m.name == loopModeName,
      orElse: () => RingtoneLoopMode.loop1Min,
    );

    _volume = prefs.getDouble('alert_volume') ?? 1.0;
    _soundEnabled = prefs.getBool('alert_sound_enabled') ?? true;
    _vibrationEnabled = prefs.getBool('alert_vibration_enabled') ?? true;
    await _player.setVolume(_volume);
  }

  Future<void> setSound(AlertSound sound) async {
    _currentSound = sound;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_sound', sound.name);
  }

  Future<void> setLoopMode(RingtoneLoopMode mode) async {
    _loopMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_loop_mode', mode.name);
  }

  Future<void> setVolume(double vol) async {
    _volume = vol;
    await _player.setVolume(vol);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('alert_volume', vol);
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alert_sound_enabled', enabled);
    if (!enabled) {
      await stop();
    }
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    _vibrationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alert_vibration_enabled', enabled);
  }

  Future<void> playAlertSound({AlertSound? soundOverride, bool isManualTest = false}) async {
    if (!_soundEnabled && !isManualTest) return;
    try {
      final soundToPlay = soundOverride ?? _currentSound;
      _stopTimer?.cancel();
      await _player.stop();
      await _player.setVolume(_volume);

      if (isManualTest || _loopMode == RingtoneLoopMode.playOnce) {
        await _player.setReleaseMode(ReleaseMode.release);
      } else {
        await _player.setReleaseMode(ReleaseMode.loop);
        if (_loopMode.seconds > 0) {
          _stopTimer = Timer(Duration(seconds: _loopMode.seconds), () {
            stop();
          });
        }
      }

      await _player.play(AssetSource('sounds/${soundToPlay.fileName}'));
      _isPlaying = true;

      if (_vibrationEnabled && !isManualTest) {
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      // Audio playback fallback
    }
  }

  Future<void> testSound(AlertSound sound) async {
    await playAlertSound(soundOverride: sound, isManualTest: true);
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    try {
      await _player.stop();
    } catch (e) {
      // Ignore
    }
    _isPlaying = false;
  }
}
