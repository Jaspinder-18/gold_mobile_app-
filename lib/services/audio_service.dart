import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AlertSound {
  alarmClock('Alarm Clock (Loud Digital)', 'alarm_clock.wav'),
  reminderBell('Reminder Bell (Melodic Chime)', 'reminder_bell.wav'),
  radarAlert('Radar Alert (Tactical Ping)', 'radar_alert.wav'),
  cyberSiren('Cyber Siren (Emergency)', 'cyber_siren.wav');

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
  double _volume = 1.0;
  bool _soundEnabled = true;

  AlertSound get currentSound => _currentSound;
  double get volume => _volume;
  bool get soundEnabled => _soundEnabled;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final soundName = prefs.getString('alert_sound') ?? AlertSound.alarmClock.name;
    _currentSound = AlertSound.values.firstWhere(
      (s) => s.name == soundName,
      orElse: () => AlertSound.alarmClock,
    );
    _volume = prefs.getDouble('alert_volume') ?? 1.0;
    _soundEnabled = prefs.getBool('alert_sound_enabled') ?? true;
    await _player.setVolume(_volume);
  }

  Future<void> setSound(AlertSound sound) async {
    _currentSound = sound;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_sound', sound.name);
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
  }

  Future<void> playAlertSound({AlertSound? soundOverride}) async {
    if (!_soundEnabled) return;
    try {
      final soundToPlay = soundOverride ?? _currentSound;
      await _player.stop();
      await _player.setVolume(_volume);
      await _player.play(AssetSource('sounds/${soundToPlay.fileName}'));
    } catch (e) {
      // Audio playback fallback
    }
  }

  Future<void> testSound(AlertSound sound) async {
    await playAlertSound(soundOverride: sound);
  }

  Future<void> stop() async {
    await _player.stop();
  }
}
