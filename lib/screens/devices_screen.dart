import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/socket_service.dart';
import 'auth_screen.dart';

class DeviceItem {
  final String token;
  final String platform;
  final String deviceName;
  final DateTime lastActiveAt;

  DeviceItem({
    required this.token,
    required this.platform,
    required this.deviceName,
    required this.lastActiveAt,
  });

  factory DeviceItem.fromJson(Map<String, dynamic> json) {
    return DeviceItem(
      token: json['token']?.toString() ?? '',
      platform: json['platform']?.toString().toUpperCase() ?? 'ANDROID',
      deviceName: json['deviceName']?.toString() ?? 'Mobile Device',
      lastActiveAt: json['lastActiveAt'] != null 
          ? DateTime.tryParse(json['lastActiveAt'].toString()) ?? DateTime.now() 
          : DateTime.now(),
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
  String? _deletingToken;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  Future<String> _resolveServerUrl() async {
    final socketUrl = SocketService().serverUrl;
    if (socketUrl.isNotEmpty) return socketUrl;
    return 'https://gold-server-dbbq.onrender.com';
  }

  Future<void> _fetchDevices() async {
    final user = AuthService().currentUser;
    if (user == null || user.email.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final response = await http.get(
        Uri.parse('$cleanUrl/api/auth/devices?email=${Uri.encodeComponent(user.email)}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = json.decode(response.body);
        if (body['success'] == true && body['data'] is List) {
          final list = (body['data'] as List)
              .map((d) => DeviceItem.fromJson(d))
              .toList();
          if (mounted) {
            setState(() {
              _devices = list;
              _isLoading = false;
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load devices. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error loading devices.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeDevice(DeviceItem device) async {
    final user = AuthService().currentUser;
    if (user == null) return;

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
          'Are you sure you want to remove "${device.deviceName}" from this account?\n\nThis device will no longer receive price touch push alarms.',
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

    setState(() => _deletingToken = device.token);

    try {
      final serverUrl = await _resolveServerUrl();
      final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final response = await http.post(
        Uri.parse('$cleanUrl/api/auth/devices/remove'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': user.email,
          'token': device.token,
        }),
      ).timeout(const Duration(seconds: 10));

      final body = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && body['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('Device "${device.deviceName}" unlinked.', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        }
        await _fetchDevices();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              content: Text(body['error'] ?? 'Failed to remove device.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Network error unlinking device.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingToken = null);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            const Icon(Icons.copy, color: Color(0xFFF59E0B), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('$label copied to clipboard!', style: const TextStyle(color: Colors.white, fontSize: 12))),
          ],
        ),
      ),
    );
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
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.devices_other, color: Color(0xFFF59E0B), size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Account Required',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please sign in with your email to inspect, manage, and unlink devices sharing your price touch alerts.',
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

    final localFcmToken = NotificationService().fcmToken ?? '';

    return RefreshIndicator(
      color: const Color(0xFFF59E0B),
      backgroundColor: const Color(0xFF0F172A),
      onRefresh: _fetchDevices,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          // Header Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
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
                          'DEVICE & FCM TOKEN REGISTRY',
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
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
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
                'LINKED FCM PUSH DEVICES',
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
                color: const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
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
                  'No registered devices found for this account.\nSign into your devices to link them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                ),
              ),
            )
          else
            ..._devices.map((dev) {
              final isThisDevice = localFcmToken.isNotEmpty && dev.token == localFcmToken;
              final isDeleting = _deletingToken == dev.token;

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
                    color: isThisDevice ? const Color(0xFFF59E0B).withOpacity(0.5) : const Color(0xFF1E293B),
                    width: isThisDevice ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Device Info + Delete Action
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: platformColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: platformColor.withOpacity(0.3)),
                          ),
                          child: Icon(platformIcon, color: platformColor, size: 18),
                        ),
                        const SizedBox(width: 10),
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
                                  if (isThisDevice) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
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
                              const SizedBox(height: 2),
                              Text(
                                '${dev.platform} · Active: ${dev.lastActiveAt.toLocal().toString().split('.')[0]}',
                                style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
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

                    const SizedBox(height: 10),

                    // FCM Token Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF030712),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.key, color: Colors.white38, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              dev.token.length > 28
                                  ? '${dev.token.substring(0, 14)}...${dev.token.substring(dev.token.length - 12)}'
                                  : dev.token,
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () => _copyToClipboard(dev.token, 'FCM Token'),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                children: const [
                                  Icon(Icons.copy, color: Color(0xFFF59E0B), size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'COPY',
                                    style: TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
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
