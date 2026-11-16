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
  final bool isServiceable;
  final double? latitude;
  final double? longitude;

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
    this.isServiceable = true,
    this.latitude,
    this.longitude,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      phoneNumber: (json['phone_number'] ?? '').toString(),
      country: (json['country'] ?? 'Philippines').toString(),
      provinceCode: (json['province_code'] ?? '').toString(),
      province: (json['province'] ?? '').toString(),
      municipalityCode: (json['municipality_code'] ?? '').toString(),
      municipality: (json['municipality'] ?? '').toString(),
      barangayCode: json['barangay_code']?.toString(),
      barangay: json['barangay']?.toString(),
      postcode: (json['postcode'] ?? '').toString(),
      streetAddress: (json['street_address'] ?? '').toString(),
      buildingDetails: json['building_details']?.toString(),
      isDefault: json['is_default'] == 1 || json['is_default'] == true,
      isServiceable:
          json['is_serviceable'] != false && json['is_serviceable'] != 0,
      latitude: json['latitude'] != null
          ? double.tryParse('${json['latitude']}')
          : null,
      longitude: json['longitude'] != null
          ? double.tryParse('${json['longitude']}')
          : null,
    );
  }

  String get recipientName => '$firstName $lastName'.trim();

  String get fullAddress {
    final parts = [
      buildingDetails,
      streetAddress,
      barangay,
      municipality,
      province,
      postcode,
    ];
    return parts
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(', ');
  }
}
