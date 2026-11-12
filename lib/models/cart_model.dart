import 'product_model.dart';

class CartItem {
  final int id;
  final Product product;
  int quantity;
  final String? variant;
  final String? subVariant;
  bool isSelected;
  bool isSyncing;

  CartItem({
    required this.id,
    required this.product,
    required this.quantity,
    this.variant,
    this.subVariant,
    this.isSelected = true,
    this.isSyncing = false,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      product: Product.fromJson(
        json['product'] is Map
            ? Map<String, dynamic>.from(json['product'])
            : <String, dynamic>{},
      ),
      quantity: int.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
      variant: json['variant']?.toString(),
      subVariant: json['sub_variant']?.toString(),
    );
  }

  double get activePrice {
    double basePrice = product.price;
    if (variant != null &&
        variant!.isNotEmpty &&
        product.variants != null &&
        product.variants!['items'] is List) {
      for (final v in (product.variants!['items'] as List)) {
        if (v is Map && v['name']?.toString() == variant) {
          if (subVariant == null || subVariant!.isEmpty) {
            basePrice = double.tryParse(
                    v['price']?.toString() ?? basePrice.toString()) ??
                basePrice;
          } else if (v['subs'] is List) {
            for (final sub in (v['subs'] as List)) {
              if (sub is Map && sub['name']?.toString() == subVariant) {
                basePrice = double.tryParse(sub['price']?.toString() ??
                        v['price']?.toString() ??
                        basePrice.toString()) ??
                    basePrice;
              }
            }
          }
        }
      }
    }
    return basePrice;
  }

  double get discountedPrice {
    if (product.discount > 0) {
      return activePrice - (activePrice * (product.discount / 100));
    }
    return activePrice;
  }

  String get storeName {
    return product.sellerProfile?.businessName ?? 'Storkia Direct';
  }

  bool get isStoreOnVacation {
    return product.isStoreOnVacation ||
        (product.sellerProfile?.isOnVacation ?? false);
  }

  int get maxStock {
    int stock = product.stockQuantity;
    if (variant != null &&
        variant!.isNotEmpty &&
        product.variants != null &&
        product.variants!['items'] is List) {
      for (final v in (product.variants!['items'] as List)) {
        if (v is Map && v['name']?.toString() == variant) {
          if (subVariant == null || subVariant!.isEmpty) {
            stock = int.tryParse(v['stock']?.toString() ?? stock.toString()) ??
                stock;
          } else if (v['subs'] is List) {
            for (final sub in (v['subs'] as List)) {
              if (sub is Map && sub['name']?.toString() == subVariant) {
                stock = int.tryParse(
                        sub['stock']?.toString() ?? stock.toString()) ??
                    stock;
              }
            }
          }
        }
      }
    }
    if (product.perBuyerLimit > 0 && stock > product.perBuyerLimit) {
      return product.perBuyerLimit;
    }
    return stock;
  }

  String get variantLabel {
    final parts = [variant, subVariant]
        .where((e) => e != null && e.trim().isNotEmpty)
        .map((e) => e!.trim())
        .toList();
    return parts.join(' / ');
  }

  String get imageUrl {
    String img = product.pictures.isNotEmpty ? product.pictures.first : '';
    if (variant != null &&
        variant!.isNotEmpty &&
        product.variants != null &&
        product.variants!['items'] is List) {
      for (final v in (product.variants!['items'] as List)) {
        if (v is Map && v['name']?.toString() == variant) {
          if (subVariant == null || subVariant!.isEmpty) {
            if (v['image'] != null && v['image'].toString().isNotEmpty) {
              img = v['image'].toString();
            }
          } else if (v['subs'] is List) {
            for (final sub in (v['subs'] as List)) {
              if (sub is Map && sub['name']?.toString() == subVariant) {
                final subImg = sub['image']?.toString();
                final varImg = v['image']?.toString();
                if (subImg != null && subImg.isNotEmpty) {
                  img = subImg;
                } else if (varImg != null && varImg.isNotEmpty) {
                  img = varImg;
                }
              }
            }
          }
        }
      }
    }
    return img;
  }
}
