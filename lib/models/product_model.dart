import 'dart:convert';
import 'seller_profile_model.dart';

typedef JsonMap = Map<String, dynamic>;

class ProductSpecification {
  final int id;
  final String title;
  final String description;

  ProductSpecification({
    required this.id,
    required this.title,
    required this.description,
  });

  factory ProductSpecification.fromJson(JsonMap json) {
    return ProductSpecification(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }

  JsonMap toJson() => {
        'id': id,
        'title': title,
        'description': description,
      };
}

class Product {
  final int id;
  final int? userId;
  final String name;
  final String? category;
  final String? subcategory;
  final String description;
  final String? additionalDescriptions;
  final double price;
  final String weight;
  final double discount;
  final int stockQuantity;
  final List<String> pictures;
  final JsonMap? variants;
  final SellerProfile? sellerProfile;
  final List<ProductSpecification> specifications;
  final double avgRating;
  final int soldCount;
  final int perBuyerLimit;
  final bool isWishlisted;
  final bool isUnavailable;
  final bool _isSoldOutFlag;
  final JsonMap? dealPricing;

  Product({
    required this.id,
    this.userId,
    required this.name,
    this.category,
    this.subcategory,
    required this.description,
    this.additionalDescriptions,
    required this.price,
    required this.weight,
    required this.discount,
    required this.stockQuantity,
    required this.pictures,
    this.variants,
    this.sellerProfile,
    this.specifications = const [],
    this.avgRating = 0.0,
    this.soldCount = 0,
    this.perBuyerLimit = 0,
    this.isWishlisted = false,
    this.isUnavailable = false,
    bool isSoldOut = false,
    this.dealPricing,
  }) : _isSoldOutFlag = isSoldOut;

  bool get isStoreOnVacation => sellerProfile?.isOnVacation ?? false;

  int get effectiveStock {
    if (variants != null &&
        variants!['items'] is List &&
        (variants!['items'] as List).isNotEmpty) {
      int total = 0;
      for (final item in (variants!['items'] as List)) {
        if (item is! Map) continue;
        if (item['is_archived'] == true ||
            item['status']?.toString() == 'Disapproved') {
          continue;
        }
        if (item['subs'] is List && (item['subs'] as List).isNotEmpty) {
          for (final sub in (item['subs'] as List)) {
            if (sub is! Map) continue;
            if (sub['is_archived'] == true ||
                sub['status']?.toString() == 'Disapproved') {
              continue;
            }
            total += int.tryParse(sub['stock']?.toString() ?? '0') ?? 0;
          }
        } else {
          total += int.tryParse(item['stock']?.toString() ?? '0') ?? 0;
        }
      }
      return total;
    }
    return stockQuantity;
  }

  bool get isSoldOut => _isSoldOutFlag || effectiveStock <= 0;

  double get effectiveDiscountPercent {
    if (dealPricing != null && dealPricing!['has_promo'] == true) {
      final dPct = double.tryParse(
          dealPricing!['discount_percentage']?.toString() ?? '0');
      if (dPct != null && dPct > 0) return dPct;
    }
    return discount;
  }

  double get discountedPrice {
    if (dealPricing != null && dealPricing!['has_promo'] == true) {
      final dPrice =
          double.tryParse(dealPricing!['effective_price']?.toString() ?? '');
      if (dPrice != null && dPrice > 0) return dPrice;
    }
    final pct = effectiveDiscountPercent;
    if (pct > 0) {
      return price - (price * (pct / 100));
    }
    return price;
  }

  factory Product.fromJson(JsonMap json) {
    List<String> parsedPictures = [];
    final dynamic rawPics = json['pictures'];
    if (rawPics is List) {
      parsedPictures = [
        for (final p in rawPics)
          if (p != null && p.toString().trim().isNotEmpty) p.toString().trim(),
      ];
    } else if (rawPics is String && rawPics.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPics);
        if (decoded is List) {
          parsedPictures = [
            for (final p in decoded)
              if (p != null && p.toString().trim().isNotEmpty)
                p.toString().trim(),
          ];
        } else {
          parsedPictures = [rawPics.trim()];
        }
      } catch (_) {
        parsedPictures = [rawPics.trim()];
      }
    }
    if (parsedPictures.isEmpty && json['image'] != null) {
      parsedPictures = [json['image'].toString()];
    }

    JsonMap? parsedVariants;
    final dynamic rawVars = json['raw_variants'] ?? json['variants'];
    if (rawVars is Map) {
      parsedVariants = Map<String, dynamic>.from(rawVars);
    } else if (rawVars is String && rawVars.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawVars);
        if (decoded is Map) {
          parsedVariants = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    double resolvedPrice =
        double.tryParse(json['price']?.toString() ?? '0') ?? 0.0;
    String resolvedWeight = json['weight']?.toString() ?? '';

    if ((resolvedPrice <= 0 || resolvedWeight.isEmpty) &&
        parsedVariants != null &&
        parsedVariants['items'] is List) {
      for (final item in (parsedVariants['items'] as List)) {
        if (item is! Map) continue;
        if (item['is_archived'] == true ||
            item['status']?.toString() == 'Disapproved') {
          continue;
        }
        if (resolvedPrice <= 0 && item['price'] != null) {
          resolvedPrice =
              double.tryParse(item['price'].toString()) ?? resolvedPrice;
        }
        if (resolvedWeight.isEmpty && item['weight'] != null) {
          resolvedWeight = item['weight'].toString();
        }
        if (item['subs'] is List) {
          for (final sub in (item['subs'] as List)) {
            if (sub is! Map) continue;
            if (sub['is_archived'] == true ||
                sub['status']?.toString() == 'Disapproved') {
              continue;
            }
            if (resolvedPrice <= 0 && sub['price'] != null) {
              resolvedPrice =
                  double.tryParse(sub['price'].toString()) ?? resolvedPrice;
            }
            if (resolvedWeight.isEmpty && sub['weight'] != null) {
              resolvedWeight = sub['weight'].toString();
            }
            if (resolvedPrice > 0) break;
          }
        }
        if (resolvedPrice > 0) break;
      }
    }
    if (resolvedWeight.isEmpty) {
      resolvedWeight = '0.2';
    }

    SellerProfile? resolvedSeller;
    if (json['seller_profile'] is Map) {
      resolvedSeller = SellerProfile.fromJson(
          Map<String, dynamic>.from(json['seller_profile'] as Map));
    } else if (json['seller'] is Map) {
      resolvedSeller = SellerProfile.fromJson(
          Map<String, dynamic>.from(json['seller'] as Map));
    } else if (json['user'] is Map &&
        (json['user'] as Map)['seller_profile'] is Map) {
      resolvedSeller = SellerProfile.fromJson(Map<String, dynamic>.from(
          (json['user'] as Map)['seller_profile'] as Map));
    }

    List<ProductSpecification> parsedSpecs = [];
    if (json['specifications'] is List) {
      for (final s in (json['specifications'] as List)) {
        if (s is Map) {
          parsedSpecs
              .add(ProductSpecification.fromJson(Map<String, dynamic>.from(s)));
        }
      }
    }

    final String? approvalStatus = json['approval_status']?.toString() ??
        (json['approval'] is Map
            ? (json['approval'] as Map)['status']?.toString()
            : null);

    final bool resolvedUnavailable = json['is_unavailable'] == true ||
        json['deleted_at'] != null ||
        (approvalStatus != null && approvalStatus != 'Approved');

    return Product(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      userId: int.tryParse(json['user_id']?.toString() ?? '') ??
          resolvedSeller?.userId,
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString(),
      subcategory: json['subcategory']?.toString(),
      description: json['description']?.toString() ?? '',
      additionalDescriptions: json['additional_descriptions']?.toString(),
      price: resolvedPrice,
      weight: resolvedWeight,
      discount: double.tryParse(json['discount']?.toString() ?? '0') ?? 0.0,
      stockQuantity:
          int.tryParse(json['stock_quantity']?.toString() ?? '0') ?? 0,
      pictures: parsedPictures,
      variants: parsedVariants,
      sellerProfile: resolvedSeller,
      specifications: parsedSpecs,
      avgRating: double.tryParse(
              (json['avg_rating'] ?? json['product_avg_rating'] ?? '0')
                  .toString()) ??
          0.0,
      soldCount: int.tryParse(
              (json['sold_count'] ?? json['total_sold_units'] ?? '0')
                  .toString()) ??
          0,
      perBuyerLimit:
          int.tryParse(json['per_buyer_limit']?.toString() ?? '0') ?? 0,
      isWishlisted: json['is_wishlisted'] == true,
      isUnavailable: resolvedUnavailable,
      isSoldOut: json['is_sold_out'] == true,
      dealPricing: json['deal_pricing'] is Map
          ? Map<String, dynamic>.from(json['deal_pricing'] as Map)
          : null,
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'category': category,
      'subcategory': subcategory,
      'description': description,
      'additional_descriptions': additionalDescriptions,
      'price': price,
      'weight': weight,
      'discount': discount,
      'stock_quantity': stockQuantity,
      'pictures': pictures,
      'variants': variants,
      'seller_profile': sellerProfile?.toJson(),
      'specifications': [for (final s in specifications) s.toJson()],
      'avg_rating': avgRating,
      'sold_count': soldCount,
      'per_buyer_limit': perBuyerLimit,
      'is_wishlisted': isWishlisted,
      'is_unavailable': isUnavailable,
      'is_sold_out': isSoldOut,
      'deal_pricing': dealPricing,
    };
  }
}
