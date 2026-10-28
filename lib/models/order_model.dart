class SellerOrder {
  final int id;
  final String sellerOrderNumber;
  final String status;
  final String paymentStatus;
  final double totalAmount;
  final String businessName;
  final String? logoPath;
  final List<OrderItem> items;
  final String createdAt;

  SellerOrder({
    required this.id,
    required this.sellerOrderNumber,
    required this.status,
    required this.paymentStatus,
    required this.totalAmount,
    required this.businessName,
    this.logoPath,
    required this.items,
    required this.createdAt,
  });

  factory SellerOrder.fromJson(Map<String, dynamic> json) {
    return SellerOrder(
      id: json['id'],
      sellerOrderNumber: json['seller_order_number'] ?? '',
      status: json['status'] ?? 'pending',
      paymentStatus: json['payment_status'] ?? 'unpaid',
      totalAmount: double.tryParse(json['total_amount'].toString()) ?? 0.0,
      businessName: json['seller_profile']?['business_name'] ?? 'Unknown Store',
      logoPath: json['seller_profile']?['logo_path'],
      items: (json['items'] as List?)
              ?.map((i) => OrderItem.fromJson(i))
              .toList() ??
          [],
      createdAt: json['created_at'] ?? '',
    );
  }

  String get readableStatus {
    return status.replaceAll('_', ' ').toUpperCase();
  }
}

class OrderItem {
  final int id;
  final String productName;
  final String? productImage;
  final String? variantName;
  final String? subVariantName;
  final double discountedUnitPrice;
  final int quantity;

  OrderItem({
    required this.id,
    required this.productName,
    this.productImage,
    this.variantName,
    this.subVariantName,
    required this.discountedUnitPrice,
    required this.quantity,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'],
      productName: json['product_name'] ?? '',
      productImage: json['product_image'],
      variantName: json['variant_name'],
      subVariantName: json['sub_variant_name'],
      discountedUnitPrice:
          double.tryParse(json['discounted_unit_price'].toString()) ?? 0.0,
      quantity: json['quantity'] ?? 1,
    );
  }
}
