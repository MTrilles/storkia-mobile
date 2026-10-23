class SellerProfile {
  final int id;
  final int userId;
  final String businessName;
  final String lineOfBusiness;
  final String? logoPath;
  final String province;
  final String municipality;
  final String? createdAt;

  SellerProfile({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.lineOfBusiness,
    this.logoPath,
    required this.province,
    required this.municipality,
    this.createdAt,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    return SellerProfile(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      businessName: json['business_name'] ?? 'Official Store',
      lineOfBusiness: json['line_of_business'] ?? '',
      logoPath: json['logo_path'],
      province: json['province'] ?? '',
      municipality: json['municipality'] ?? '',
      createdAt: json['created_at'],
    );
  }
}
