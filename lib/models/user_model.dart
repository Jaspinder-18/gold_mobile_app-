class UserModel {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final int activeDevicesCount;
  final String? token;
  final bool notificationsEnabled;

  String? get sessionToken => token;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.role = 'USER',
    this.activeDevicesCount = 1,
    this.token,
    this.notificationsEnabled = true,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, {String? sessionToken}) {
    return UserModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? 'Trader',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'USER',
      activeDevicesCount: int.tryParse(json['activeDevicesCount']?.toString() ?? '1') ?? 1,
      token: sessionToken ?? json['token']?.toString(),
      notificationsEnabled: json['notificationsEnabled'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'role': role,
      'activeDevicesCount': activeDevicesCount,
      'token': token,
      'notificationsEnabled': notificationsEnabled,
    };
  }
}
