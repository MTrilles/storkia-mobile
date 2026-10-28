class Address {
  final int id;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String country;
  final String provinceCode;
  final String province;
  final String municipalityCode;
  final String municipality;
  final String? barangayCode;
  final String? barangay;
  final String postcode;
  final String streetAddress;
  final String? buildingDetails;
  final bool isDefault;

  Address({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.country,
    required this.provinceCode,
    required this.province,
    required this.municipalityCode,
    required this.municipality,
    this.barangayCode,
    this.barangay,
    required this.postcode,
    required this.streetAddress,
    this.buildingDetails,
    required this.isDefault,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      id: json['id'],
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      country: json['country'] ?? 'Philippines',
      provinceCode: json['province_code'] ?? '',
      province: json['province'] ?? '',
      municipalityCode: json['municipality_code'] ?? '',
      municipality: json['municipality'] ?? '',
      barangayCode: json['barangay_code'],
      barangay: json['barangay'],
      postcode: json['postcode'] ?? '',
      streetAddress: json['street_address'] ?? '',
      buildingDetails: json['building_details'],
      isDefault: json['is_default'] == 1 || json['is_default'] == true,
    );
  }

  String get recipientName => '$firstName $lastName';

  String get fullAddress {
    final parts = [
      buildingDetails,
      streetAddress,
      barangay,
      municipality,
      province,
      postcode
    ];
    return parts.where((part) => part != null && part.isNotEmpty).join(', ');
  }
}
