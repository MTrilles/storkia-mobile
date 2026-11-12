typedef JsonMap = Map<String, dynamic>;

class SellerProfile {
  final int id;
  final int userId;
  final String businessName;
  final String lineOfBusiness;
  final String province;
  final String municipality;
  final String barangay;
  final String? street;
  final String? houseDetails;
  final String? contactNo;
  final String? logoPath;
  final bool isOnVacation;
  final bool isFollowing;
  final bool isOwnStore;
  final JsonMap? stats;

  SellerProfile({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.lineOfBusiness,
    required this.province,
    required this.municipality,
    required this.barangay,
    this.street,
    this.houseDetails,
    this.contactNo,
    this.logoPath,
    this.isOnVacation = false,
    this.isFollowing = false,
    this.isOwnStore = false,
    this.stats,
  });

  factory SellerProfile.fromJson(JsonMap json) {
    final String? resolvedLogo = (json['logo_path'] ??
            json['photo_url'] ??
            json['avatar_url'] ??
            json['logo'])
        ?.toString()
        .trim();

    return SellerProfile(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      businessName: (json['business_name'] ??
              json['store_name'] ??
              json['name'] ??
              'Verified Store')
          .toString(),
      lineOfBusiness:
          (json['line_of_business'] ?? json['category'] ?? '').toString(),
      province: json['province']?.toString() ?? '',
      municipality: json['municipality']?.toString() ?? '',
      barangay: json['barangay']?.toString() ?? '',
      street: json['street']?.toString(),
      houseDetails: json['house_details']?.toString(),
      contactNo: json['contact_no']?.toString(),
      logoPath: (resolvedLogo != null && resolvedLogo.isNotEmpty)
          ? resolvedLogo
          : null,
      isOnVacation:
          json['is_on_vacation'] == true || json['is_on_vacation'] == 1,
      isFollowing: json['is_following'] == true,
      isOwnStore: json['is_own_store'] == true,
      stats: json['stats'] is Map
          ? Map<String, dynamic>.from(json['stats'] as Map)
          : null,
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'user_id': userId,
      'business_name': businessName,
      'line_of_business': lineOfBusiness,
      'province': province,
      'municipality': municipality,
      'barangay': barangay,
      'street': street,
      'house_details': houseDetails,
      'contact_no': contactNo,
      'logo_path': logoPath,
      'is_on_vacation': isOnVacation,
      'is_following': isFollowing,
      'is_own_store': isOwnStore,
      'stats': stats,
    };
  }
}
