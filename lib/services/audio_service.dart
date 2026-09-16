import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
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

enum AlertNotifyMode {
  soundAndVibration('Sound & Vibration', 'Play loud alarm ringtone + haptic vibration'),
  vibrateOnly('Vibration (No Sound)', 'Repeated haptic vibration without any audio sound'),
  soundOnly('Sound Only (No Vibration)', 'Play loud alarm ringtone with vibration muted'),
  silent('Silent Notification', 'Visual screen notification banner only');

  final String label;
  final String description;
  const AlertNotifyMode(this.label, this.description);
}

enum AlertSound {
  radarAlert('Sound 1: Urgent Radar Alarm', 'radar_alert.wav'),
  alarmClock('Sound 2: Digital Alarm Clock', 'alarm_clock.wav'),
  reminderBell('Sound 3: Melodic Chime Bell', 'reminder_bell.wav'),
  vibrateOnly('Vibration Only (No Sound)', 'vibrate_only'),
  deviceSound('Device Default / System Sound', 'device_default');

  final String title;
  final String fileName;
  const AlertSound(this.title, this.fileName);
}

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  static AudioService get instance => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  AlertSound _currentSound = AlertSound.radarAlert;
  RingtoneLoopMode _loopMode = RingtoneLoopMode.loop1Min;
  double _volume = 1.0;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _isPlaying = false;
  String? _customAudioPath;
  String? _customAudioName;
  Timer? _stopTimer;
  Timer? _vibrationTimer;

  AlertSound get currentSound => _currentSound;
  RingtoneLoopMode get loopMode => _loopMode;
  double get volume => _volume;
  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get isPlaying => _isPlaying;
  String? get customAudioPath => _customAudioPath;
  String? get customAudioName => _customAudioName;

  AlertNotifyMode get notifyMode {
    if (_currentSound == AlertSound.vibrateOnly || (!_soundEnabled && _vibrationEnabled)) {
      return AlertNotifyMode.vibrateOnly;
    }
    if (_soundEnabled && _vibrationEnabled) return AlertNotifyMode.soundAndVibration;
    if (_soundEnabled && !_vibrationEnabled) return AlertNotifyMode.soundOnly;
    return AlertNotifyMode.silent;
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customAudioPath = prefs.getString('custom_audio_path');
      _customAudioName = prefs.getString('custom_audio_name');

      final soundName = prefs.getString('alert_sound') ?? AlertSound.radarAlert.name;
      _currentSound = AlertSound.values.firstWhere(
        (s) => s.name == soundName,
        orElse: () => AlertSound.radarAlert,
      );

      final loopModeName = prefs.getString('alert_loop_mode') ?? RingtoneLoopMode.loop1Min.name;
      _loopMode = RingtoneLoopMode.values.firstWhere(
        (m) => m.name == loopModeName,
        orElse: () => RingtoneLoopMode.loop1Min,
      );

      _volume = prefs.getDouble('alert_volume') ?? 1.0;
      _soundEnabled = prefs.getBool('alert_sound_enabled') ?? (_currentSound != AlertSound.vibrateOnly);
      _vibrationEnabled = prefs.getBool('alert_vibration_enabled') ?? true;

      // Configure AudioContext for loud speaker alarm usage
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
            isSpeakerphoneOn: true, // Forces sound to LOUD speaker instead of ear receiver
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

  Future<void> setNotifyMode(AlertNotifyMode mode) async {
    switch (mode) {
      case AlertNotifyMode.soundAndVibration:
        _soundEnabled = true;
        _vibrationEnabled = true;
        break;
      case AlertNotifyMode.vibrateOnly:
        _soundEnabled = false;
        _vibrationEnabled = true;
        break;
      case AlertNotifyMode.soundOnly:
        _soundEnabled = true;
        _vibrationEnabled = false;
        break;
      case AlertNotifyMode.silent:
        _soundEnabled = false;
        _vibrationEnabled = false;
        break;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alert_sound_enabled', _soundEnabled);
    await prefs.setBool('alert_vibration_enabled', _vibrationEnabled);
    if (!_soundEnabled) {
      await _player.stop();
    }
    if (!_vibrationEnabled) {
      _vibrationTimer?.cancel();
    }
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

  Future<bool> pickAndSetCustomAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'ogg', 'aac', 'flac', 'opus', 'wma'],
      );

      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;
        _customAudioPath = path;
        _customAudioName = name;
        _currentSound = AlertSound.deviceSound;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('custom_audio_path', path);
        await prefs.setString('custom_audio_name', name);
        await prefs.setString('alert_sound', AlertSound.deviceSound.name);
        return true;
      }
    } catch (e) {
      debugPrint('[AudioService] pickAndSetCustomAudio error: $e');
    }
    return false;
  }

  Future<void> playAlertSound({AlertSound? soundOverride, bool isManualTest = false}) async {
    // If both sound and vibration are disabled, and it's not a manual test, do nothing
    if (!_soundEnabled && !_vibrationEnabled && !isManualTest) return;

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

      if (_soundEnabled || isManualTest) {
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

        if (soundToPlay == AlertSound.vibrateOnly) {
          // Vibration only mode: audio is muted
        } else if (soundToPlay == AlertSound.deviceSound) {
          try {
            await SystemSound.play(SystemSoundType.alert);
          } catch (_) {}
          await _playAssetFile('reminder_bell.wav');
        } else {
          await _playAssetFile(soundToPlay.fileName);
        }
      }

      _isPlaying = true;

      // Start periodic vibration during alarm if enabled (even if sound is muted in Vibrate Only mode)
      if (_vibrationEnabled || soundToPlay == AlertSound.vibrateOnly || isManualTest) {
        HapticFeedback.heavyImpact();
        if (!isManualTest && _loopMode != RingtoneLoopMode.playOnce) {
          _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
            if (_isPlaying) {
              HapticFeedback.heavyImpact();
            } else {
              _vibrationTimer?.cancel();
            }
          });
          if (!_soundEnabled && _loopMode.seconds > 0) {
            _stopTimer = Timer(Duration(seconds: _loopMode.seconds), () {
              stop();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[AudioService] playAlertSound error: $e');
    }
  }

  Future<void> _playAssetFile(String fileName) async {
    // 1. Primary: Direct in-memory byte buffer from rootBundle (100% reliable across Android & iOS)
    try {
      final byteData = await rootBundle.load('assets/sounds/$fileName');
      final bytes = byteData.buffer.asUint8List();
      await _player.play(BytesSource(bytes));
      return;
    } catch (e) {
      debugPrint('[AudioService] BytesSource failed ($e), falling back to AssetSource...');
    }

    // 2. Fallback: AssetSource with sounds/ prefix
    try {
      await _player.play(AssetSource('sounds/$fileName'));
      return;
    } catch (e2) {
      debugPrint('[AudioService] AssetSource(sounds/$fileName) failed ($e2), trying direct asset path...');
    }

    // 3. Fallback: Full path
    try {
      await _player.play(AssetSource('assets/sounds/$fileName'));
    } catch (e3) {
      debugPrint('[AudioService] All asset playback methods failed: $e3');
    }
  }

  Future<void> testSound(AlertSound sound) async {
    if (sound == AlertSound.vibrateOnly) {
      HapticFeedback.heavyImpact();
      return;
    }
    await playAlertSound(soundOverride: sound, isManualTest: true);
  }

  static AudioPlayer? _activeBgPlayer;

  Future<void> stop() async {
    _stopTimer?.cancel();
    _vibrationTimer?.cancel();
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[AudioService] stop error: $e');
    }
    try {
      if (_activeBgPlayer != null) {
        await _activeBgPlayer!.stop();
        await _activeBgPlayer!.dispose();
        _activeBgPlayer = null;
      }
    } catch (_) {}
    _isPlaying = false;
  }

  Future<void> stopAlarm() async {
    await stopAllAudio();
  }

  static Future<void> stopAllAudio() async {
    try {
      if (_activeBgPlayer != null) {
        await _activeBgPlayer!.stop();
        await _activeBgPlayer!.dispose();
        _activeBgPlayer = null;
      }
    } catch (_) {}
    try {
      await _instance.stop();
    } catch (_) {}
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static Future<void> playAlertSoundDirect({String fileName = 'alarm_clock.wav', int loopSeconds = 30}) async {
    try {
      // Stop any existing background player first
      try {
        if (_activeBgPlayer != null) {
          await _activeBgPlayer!.stop();
          await _activeBgPlayer!.dispose();
          _activeBgPlayer = null;
        }
      } catch (_) {}

      final AudioPlayer bgPlayer = AudioPlayer();
      _activeBgPlayer = bgPlayer;

      try {
        await bgPlayer.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: true,
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
      } catch (_) {}
      try {
        await bgPlayer.setVolume(1.0);
      } catch (_) {}
      try {
        await bgPlayer.setReleaseMode(ReleaseMode.loop);
      } catch (_) {}
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}

      bool playedOk = false;
      try {
        final byteData = await rootBundle.load('assets/sounds/$fileName');
        final bytes = byteData.buffer.asUint8List();
        await bgPlayer.play(BytesSource(bytes));
        playedOk = true;
      } catch (_) {}
      if (!playedOk) {
        try {
          await bgPlayer.play(AssetSource('sounds/$fileName'));
          playedOk = true;
        } catch (_) {}
      }
      if (!playedOk) {
        try {
          await bgPlayer.play(AssetSource('assets/sounds/$fileName'));
          playedOk = true;
        } catch (_) {}
      }

      if (playedOk && loopSeconds > 0) {
        Timer(Duration(seconds: loopSeconds), () async {
          try {
            if (_activeBgPlayer == bgPlayer) {
              await bgPlayer.stop();
              await bgPlayer.dispose();
              _activeBgPlayer = null;
            }
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('[AudioService] playAlertSoundDirect error: $e');
    }
  }
}
