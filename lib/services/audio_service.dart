import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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
  Timer? _vibrationTimer;

  AlertSound get currentSound => _currentSound;
  RingtoneLoopMode get loopMode => _loopMode;
  double get volume => _volume;
  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get isPlaying => _isPlaying;

  Future<void> initialize() async {
    try {
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

      // Configure AudioContext for alarm clock usage
      await _applyAudioContext();
      await _player.setVolume(_volume);

      _player.onPlayerComplete.listen((_) {
        if (_loopMode == RingtoneLoopMode.playOnce) {
          _isPlaying = false;
          _vibrationTimer?.cancel();
        }
      });
    } catch (e) {
      debugPrint('[AudioService] initialize error: $e');
    }
  }

  Future<void> _applyAudioContext() async {
    try {
      await _player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('[AudioService] setAudioContext error: $e');
    }
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
    _volume = vol.clamp(0.0, 1.0);
    try {
      await _player.setVolume(_volume);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('alert_volume', _volume);
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
    if (!enabled) {
      _vibrationTimer?.cancel();
    }
  }

  Future<void> playAlertSound({AlertSound? soundOverride, bool isManualTest = false}) async {
    if (!_soundEnabled && !isManualTest) return;

    try {
      final soundToPlay = soundOverride ?? _currentSound;

      // If already playing for the active alarm and it's not a manual test sound change, keep playing
      if (_isPlaying && !isManualTest && soundOverride == null) {
        return;
      }

      _stopTimer?.cancel();
      _vibrationTimer?.cancel();

      try {
        await _player.stop();
      } catch (_) {}

      await _applyAudioContext();
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

      await _playAssetFile(soundToPlay.fileName);
      _isPlaying = true;

      // Start periodic vibration during alarm if enabled
      if (_vibrationEnabled) {
        HapticFeedback.heavyImpact();
        if (!isManualTest && _loopMode != RingtoneLoopMode.playOnce) {
          _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
            if (_isPlaying) {
              HapticFeedback.heavyImpact();
            } else {
              _vibrationTimer?.cancel();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[AudioService] playAlertSound error: $e');
    }
  }

  Future<void> _playAssetFile(String fileName) async {
    // 1. Primary: AssetSource with default 'assets/' prefix
    try {
      await _player.play(AssetSource('sounds/$fileName'));
      return;
    } catch (e) {
      debugPrint('[AudioService] AssetSource(sounds/$fileName) failed ($e), trying rootBundle memory stream...');
    }

    // 2. Fallback: Direct rootBundle byte buffer loading (100% reliable)
    try {
      final byteData = await rootBundle.load('assets/sounds/$fileName');
      final bytes = byteData.buffer.asUint8List();
      await _player.play(BytesSource(bytes));
      return;
    } catch (e2) {
      debugPrint('[AudioService] BytesSource fallback failed ($e2), trying direct asset path...');
    }

    // 3. Fallback: Full path
    try {
      await _player.play(AssetSource('assets/sounds/$fileName'));
    } catch (e3) {
      debugPrint('[AudioService] All asset playback methods failed: $e3');
    }
  }

  Future<void> testSound(AlertSound sound) async {
    await playAlertSound(soundOverride: sound, isManualTest: true);
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _vibrationTimer?.cancel();
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[AudioService] stop error: $e');
    }
    _isPlaying = false;
  }
}
