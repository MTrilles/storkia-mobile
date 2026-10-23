import 'seller_profile_model.dart';

class Product {
  final int id;
  final String name;
  final double price;
  final double discount;
  final List<String> pictures;
  final String description;
  final String? additionalDescriptions;
  final String weight;
  final int stockQuantity;
  final Map<String, dynamic>? variants;
  final SellerProfile? sellerProfile;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.discount,
    required this.pictures,
    this.description = '',
    this.additionalDescriptions,
    this.weight = 'Not specified',
    this.stockQuantity = 0,
    this.variants,
    this.sellerProfile,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      price: double.tryParse(json['price'].toString()) ?? 0.0,
      discount: double.tryParse(json['discount'].toString()) ?? 0.0,
      pictures:
          json['pictures'] != null ? List<String>.from(json['pictures']) : [],
      description: json['description'] ?? '',
      additionalDescriptions: json['additional_descriptions'],
      weight: json['weight']?.toString() ?? 'Not specified',
      stockQuantity: int.tryParse(json['stock_quantity'].toString()) ?? 0,
      variants: json['variants'] != null && json['variants'] is Map
          ? Map<String, dynamic>.from(json['variants'])
          : null,
      sellerProfile: json['seller_profile'] != null
          ? SellerProfile.fromJson(json['seller_profile'])
          : null,
    );
  }

  double get discountedPrice {
    if (discount > 0) {
      return price - (price * (discount / 100));
    }
    return price;
  }
}
