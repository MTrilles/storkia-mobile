typedef JsonMap = Map<String, dynamic>;

class UserModel {
  final int id;
  final String firstName;
  final String lastName;
  final String? middleInitial;
  final String email;
  final String? contactNo;
  final String role;
  final String? sex;
  final String? birthday;
  final String? username;
  final String? avatarPath;
  final String? passwordChangedAt;
  final String? formattedPasswordLastUpdated;
  final String identityVerificationStatus;
  final JsonMap? sanction;

  UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleInitial,
    required this.email,
    this.contactNo,
    required this.role,
    this.sex,
    this.birthday,
    this.username,
    this.avatarPath,
    this.passwordChangedAt,
    this.formattedPasswordLastUpdated,
    this.identityVerificationStatus = 'unverified',
    this.sanction,
  });

  String get fullName => '$firstName $lastName'.trim();

  bool get isIdentityVerified =>
      identityVerificationStatus.toLowerCase() == 'verified' ||
      identityVerificationStatus.toLowerCase() == 'approved';

  bool get isBlockedFromMarketplace =>
      sanction != null && sanction!['is_blocked_from_marketplace'] == true;

  factory UserModel.fromJson(JsonMap json) {
    final JsonMap? buyerProfile = json['buyer_profile'] is Map
        ? Map<String, dynamic>.from(json['buyer_profile'] as Map)
        : (json['profile'] is Map
            ? Map<String, dynamic>.from(json['profile'] as Map)
            : null);

    final JsonMap? identityVerif = json['identity_verification'] is Map
        ? Map<String, dynamic>.from(json['identity_verification'] as Map)
        : (json['latest_identity_verification'] is Map
            ? Map<String, dynamic>.from(
                json['latest_identity_verification'] as Map)
            : null);

    String first = json['first_name']?.toString() ?? '';
    String last = json['last_name']?.toString() ?? '';
    if (first.isEmpty && last.isEmpty && json['name'] != null) {
      final parts = json['name'].toString().trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        first = parts.first;
        if (parts.length > 1) {
          last = parts.sublist(1).join(' ');
        }
      }
    }

    final String? resolvedUsername =
        (json['username'] ?? buyerProfile?['username'])?.toString();

    final String? rawAvatar = (json['avatar_url'] ??
            json['avatar_path'] ??
            json['photo_url'] ??
            json['avatar'] ??
            buyerProfile?['avatar_url'] ??
            buyerProfile?['avatar_path'] ??
            buyerProfile?['photo_url'])
        ?.toString();

    String resolvedKyc = (json['identity_verification_status'] ??
            json['kyc_status'] ??
            identityVerif?['status'] ??
            (json['is_identity_verified'] == true ? 'verified' : 'unverified'))
        .toString();

    return UserModel(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      firstName: first,
      lastName: last,
      middleInitial: json['middle_initial']?.toString(),
      email: json['email']?.toString() ?? '',
      contactNo: json['contact_no']?.toString() ?? json['phone']?.toString(),
      role: json['role']?.toString() ?? 'Buyer',
      sex: json['sex']?.toString(),
      birthday: json['birthday']?.toString(),
      username: (resolvedUsername != null && resolvedUsername.trim().isNotEmpty)
          ? resolvedUsername.trim()
          : null,
      avatarPath: (rawAvatar != null && rawAvatar.trim().isNotEmpty)
          ? rawAvatar.trim()
          : null,
      passwordChangedAt: json['password_changed_at']?.toString(),
      formattedPasswordLastUpdated:
          json['formatted_password_last_updated']?.toString() ??
              json['password_last_updated']?.toString(),
      identityVerificationStatus: resolvedKyc,
      sanction: json['sanction'] is Map
          ? Map<String, dynamic>.from(json['sanction'] as Map)
          : null,
    );
  }

  UserModel copyWith({
    String? firstName,
    String? lastName,
    String? middleInitial,
    String? email,
    String? contactNo,
    String? role,
    String? sex,
    String? birthday,
    String? username,
    String? avatarPath,
    bool clearAvatar = false,
    String? passwordChangedAt,
    String? formattedPasswordLastUpdated,
    String? identityVerificationStatus,
    JsonMap? sanction,
  }) {
    return UserModel(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleInitial: middleInitial ?? this.middleInitial,
      email: email ?? this.email,
      contactNo: contactNo ?? this.contactNo,
      role: role ?? this.role,
      sex: sex ?? this.sex,
      birthday: birthday ?? this.birthday,
      username: username ?? this.username,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      passwordChangedAt: passwordChangedAt ?? this.passwordChangedAt,
      formattedPasswordLastUpdated:
          formattedPasswordLastUpdated ?? this.formattedPasswordLastUpdated,
      identityVerificationStatus:
          identityVerificationStatus ?? this.identityVerificationStatus,
      sanction: sanction ?? this.sanction,
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'middle_initial': middleInitial,
      'email': email,
      'contact_no': contactNo,
      'role': role,
      'sex': sex,
      'birthday': birthday,
      'username': username,
      'avatar_path': avatarPath,
      'password_changed_at': passwordChangedAt,
      'formatted_password_last_updated': formattedPasswordLastUpdated,
      'identity_verification_status': identityVerificationStatus,
      'sanction': sanction,
    };
  }
}
