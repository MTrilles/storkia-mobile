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
      id: json['id'],
      product: Product.fromJson(json['product']),
      quantity: int.tryParse(json['quantity'].toString()) ?? 1,
      variant: json['variant'],
      subVariant: json['sub_variant'],
    );
  }

  double get activePrice {
    double basePrice = product.price;
    if (variant != null &&
        product.variants != null &&
        product.variants!['items'] != null) {
      for (var v in product.variants!['items']) {
        if (v['name'] == variant) {
          if (subVariant == null) {
            basePrice = double.tryParse(
                    v['price']?.toString() ?? basePrice.toString()) ??
                basePrice;
          } else if (v['subs'] != null) {
            for (var sub in v['subs']) {
              if (sub['name'] == subVariant) {
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

  int get maxStock {
    int stock = product.stockQuantity;
    if (variant != null &&
        product.variants != null &&
        product.variants!['items'] != null) {
      for (var v in product.variants!['items']) {
        if (v['name'] == variant) {
          if (subVariant == null) {
            stock = int.tryParse(v['stock']?.toString() ?? stock.toString()) ??
                stock;
          } else if (v['subs'] != null) {
            for (var sub in v['subs']) {
              if (sub['name'] == subVariant) {
                stock = int.tryParse(
                        sub['stock']?.toString() ?? stock.toString()) ??
                    stock;
              }
            }
          }
        }
      }
    }
    return stock;
  }

  String get imageUrl {
    String img = product.pictures.isNotEmpty ? product.pictures[0] : '';
    if (variant != null &&
        product.variants != null &&
        product.variants!['items'] != null) {
      for (var v in product.variants!['items']) {
        if (v['name'] == variant) {
          if (subVariant == null) {
            img = v['image'] ?? img;
          } else if (v['subs'] != null) {
            for (var sub in v['subs']) {
              if (sub['name'] == subVariant) {
                img = sub['image'] ?? v['image'] ?? img;
              }
            }
          }
        }
      }
    }
    return img;
  }
}
