import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';

class DeviceItem {
  final String id;
  final String deviceId;
  final String platform;
  final String deviceName;
  final String browser;
  final bool notificationsEnabled;
  final bool isCurrentDevice;
  final DateTime? lastActiveAt;

  DeviceItem({
    required this.id,
    required this.deviceId,
    required this.platform,
    required this.deviceName,
    required this.browser,
    required this.notificationsEnabled,
    required this.isCurrentDevice,
    this.lastActiveAt,
  });

  factory DeviceItem.fromMap(Map<String, dynamic> map) {
    DateTime? parsedDate;
    if (map['lastActiveAt'] != null) {
      parsedDate = DateTime.tryParse(map['lastActiveAt'].toString());
    }
    return DeviceItem(
      id: map['id']?.toString() ?? map['_id']?.toString() ?? '',
      deviceId: map['deviceId']?.toString() ?? '',
      platform: (map['platform']?.toString() ?? 'ANDROID').toUpperCase(),
      deviceName: map['deviceName']?.toString() ?? 'Mobile Device',
      browser: map['browser']?.toString() ?? '',
      notificationsEnabled: map['notificationsEnabled'] ?? true,
      isCurrentDevice: map['isCurrentDevice'] == true,
      lastActiveAt: parsedDate,
    );
  }

  DeviceItem copyWith({
    bool? notificationsEnabled,
  }) {
    return DeviceItem(
      id: id,
      deviceId: deviceId,
      platform: platform,
      deviceName: deviceName,
      browser: browser,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      isCurrentDevice: isCurrentDevice,
      lastActiveAt: lastActiveAt,
    );
  }
}

class DevicesScreen extends StatefulWidget {
  final VoidCallback? onBackToMonitor;

  const DevicesScreen({super.key, this.onBackToMonitor});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<DeviceItem> _devices = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _testingDeviceId;
  String? _deletingDeviceId;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  String _formatRelativeTime(DateTime? date) {
    if (date == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 45) return 'Active just now';
    if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Active ${diff.inDays}d ago';
    return 'Active ${DateFormat('MMM d, h:mm a').format(date.toLocal())}';
  }

  Future<void> _fetchDevices() async {
    final user = AuthService().currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await AuthService().getConnectedDevices();
      if (mounted) {
        setState(() {
          _devices = list.map((m) => DeviceItem.fromMap(m)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load connected devices. Please check connection.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleDeviceNotification(DeviceItem device, bool value) async {
    // Optimistic UI update
    setState(() {
      final idx = _devices.indexWhere((d) => d.deviceId == device.deviceId);
      if (idx != -1) {
        _devices[idx] = _devices[idx].copyWith(notificationsEnabled: value);
      }
    });

    final success = await AuthService().updateDeviceNotifications(device.deviceId, value);
    if (!success && mounted) {
      // Revert if failed
      setState(() {
        final idx = _devices.indexWhere((d) => d.deviceId == device.deviceId);
        if (idx != -1) {
          _devices[idx] = _devices[idx].copyWith(notificationsEnabled: !value);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Failed to update device notification preferences.'),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: value ? const Color(0xFF10B981) : const Color(0xFF64748B),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: [
              Icon(value ? Icons.notifications_active : Icons.notifications_off, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                '${device.deviceName}: Notifications ${value ? "ENABLED" : "MUTED"}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _sendTestPush(DeviceItem device) async {
    setState(() => _testingDeviceId = device.deviceId);

    final ok = await AuthService().sendDeviceTestPush(device.deviceId);

    if (mounted) {
      setState(() => _testingDeviceId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.error_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? 'Test push sent to ${device.deviceName}!'
                      : 'Failed to send test push to ${device.deviceName}.',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _removeDevice(DeviceItem device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 8),
            Text('Remove Device?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${device.deviceName}" from your account?\n\n'
          '${device.isCurrentDevice ? "⚠️ This is your CURRENT device. You will be logged out immediately." : "This device will be disconnected and will no longer receive price alerts."}',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('REMOVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deletingDeviceId = device.deviceId);

    final ok = await AuthService().removeDevice(device.deviceId);

    if (mounted) {
      setState(() => _deletingDeviceId = null);
      if (ok) {
        if (device.isCurrentDevice) {
          await AuthService().logout();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthScreen()),
              (route) => false,
            );
          }
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Device "${device.deviceName}" removed.', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
        await _fetchDevices();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Failed to remove device. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;

    if (user == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.devices_other, color: Color(0xFFF59E0B), size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Authentication Required',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please sign in to inspect, manage, and unlink devices sharing your price touch alerts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
                },
                icon: const Icon(Icons.login, size: 18, color: Colors.black),
                label: const Text('Sign In / Register', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFF59E0B),
      backgroundColor: const Color(0xFF0F172A),
      onRefresh: _fetchDevices,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.hub_rounded, color: Color(0xFFF59E0B), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'CONNECTED DEVICES & TERMINALS',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                      tooltip: 'Refresh Device List',
                      onPressed: _fetchDevices,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  user.fullName.isNotEmpty ? user.fullName : 'Trader Account',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.devices, color: Color(0xFF10B981), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '${_devices.length} Active Device(s) Synced',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'YOUR ACTIVE DEVICES',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                'SWIPE DOWN TO REFRESH',
                style: TextStyle(color: Colors.white30, fontSize: 9, fontFamily: 'monospace'),
              ),
            ],
          ),

          const SizedBox(height: 8),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
            )
          else if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _fetchDevices,
                    icon: const Icon(Icons.refresh, size: 16, color: Color(0xFFF59E0B)),
                    label: const Text('Try Again', style: TextStyle(color: Color(0xFFF59E0B))),
                  ),
                ],
              ),
            )
          else if (_devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Center(
                child: Text(
                  'No connected devices found for this account.\nSign into your devices to link them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                ),
              ),
            )
          else
            ..._devices.map((dev) {
              final isDeleting = _deletingDeviceId == dev.deviceId;
              final isTesting = _testingDeviceId == dev.deviceId;

              IconData platformIcon = Icons.smartphone;
              Color platformColor = const Color(0xFF10B981);
              if (dev.platform == 'IOS') {
                platformIcon = Icons.apple;
                platformColor = Colors.white70;
              } else if (dev.platform == 'WEB') {
                platformIcon = Icons.laptop;
                platformColor = const Color(0xFF38BDF8);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1626),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: dev.isCurrentDevice
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                        : const Color(0xFF1E293B),
                    width: dev.isCurrentDevice ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Device Info + Platform Badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: platformColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: platformColor.withValues(alpha: 0.3)),
                          ),
                          child: Icon(platformIcon, color: platformColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      dev.deviceName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (dev.isCurrentDevice) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                                      ),
                                      child: const Text(
                                        'THIS DEVICE',
                                        style: TextStyle(
                                          color: Color(0xFFF59E0B),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${dev.platform}${dev.browser.isNotEmpty ? " · ${dev.browser}" : ""} · ${_formatRelativeTime(dev.lastActiveAt)}',
                                style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        // Unlink / Delete Button
                        isDeleting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                              )
                            : IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                                tooltip: 'Remove Device',
                                onPressed: () => _removeDevice(dev),
                              ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Bottom row: Push Notification Controls & Test Push Button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF030712),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                dev.notificationsEnabled ? Icons.notifications_active : Icons.notifications_off,
                                color: dev.notificationsEnabled ? const Color(0xFFF59E0B) : Colors.white38,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                dev.notificationsEnabled ? 'Alerts Enabled' : 'Alerts Muted',
                                style: TextStyle(
                                  color: dev.notificationsEnabled ? Colors.white : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Switch(
                                value: dev.notificationsEnabled,
                                activeThumbColor: const Color(0xFFF59E0B),
                                activeTrackColor: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                inactiveThumbColor: Colors.white38,
                                inactiveTrackColor: const Color(0xFF1E293B),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (val) => _toggleDeviceNotification(dev, val),
                              ),
                            ],
                          ),
                          // Test Push Action
                          isTesting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
                                )
                              : TextButton.icon(
                                  onPressed: () => _sendTestPush(dev),
                                  icon: const Icon(Icons.send_rounded, size: 12, color: Color(0xFF38BDF8)),
                                  label: const Text(
                                    'TEST',
                                    style: TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
