import 'dart:core';

class SellerOrder {
  final int id;
  final String sellerOrderNumber;
  final String status;
  final String statusLabel;
  final String paymentStatus;
  final String effectivePaymentMethod;
  final double totalAmount;
  final String businessName;
  final String? logoPath;
  final List<OrderItem> items;
  final String createdAt;
  final bool isRatedByBuyer;
  final bool canBuyerCancelPreShipment;

  SellerOrder({
    required this.id,
    required this.sellerOrderNumber,
    required this.status,
    required this.statusLabel,
    required this.paymentStatus,
    required this.effectivePaymentMethod,
    required this.totalAmount,
    required this.businessName,
    this.logoPath,
    required this.items,
    required this.createdAt,
    this.isRatedByBuyer = false,
    this.canBuyerCancelPreShipment = false,
  });

  factory SellerOrder.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawItems = json['items'] is List
        ? List<dynamic>.from(json['items'] as List)
        : <dynamic>[];

    final Map<String, dynamic> sellerProfile = json['seller_profile'] is Map
        ? Map<String, dynamic>.from(json['seller_profile'] as Map)
        : <String, dynamic>{};

    final String rawStatus = json['status']?.toString() ?? 'pending';

    return SellerOrder(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      sellerOrderNumber: json['seller_order_number']?.toString() ?? '',
      status: rawStatus,
      statusLabel: json['status_label']?.toString() ??
          rawStatus.replaceAll('_', ' ').toUpperCase(),
      paymentStatus: json['payment_status']?.toString() ?? 'unpaid',
      effectivePaymentMethod:
          json['effective_payment_method']?.toString() ?? 'COD',
      totalAmount:
          double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0.0,
      businessName:
          sellerProfile['business_name']?.toString() ?? 'Official Store',
      logoPath: sellerProfile['logo_path']?.toString(),
      items: rawItems
          .whereType()
          .map((i) => OrderItem.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
      createdAt: json['created_at']?.toString() ?? '',
      isRatedByBuyer:
          json['is_rated_by_buyer'] == true || json['service_rating'] != null,
      canBuyerCancelPreShipment: json['can_buyer_cancel_pre_shipment'] == true,
    );
  }

  String get readableStatus => statusLabel;
}

class OrderItem {
  final int id;
  final int productId;
  final String productName;
  final String? productImage;
  final String? variantName;
  final String? subVariantName;
  final double discountedUnitPrice;
  final double lineTotal;
  final int quantity;

  OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.productImage,
    this.variantName,
    this.subVariantName,
    required this.discountedUnitPrice,
    required this.lineTotal,
    required this.quantity,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final double unitPrice =
        double.tryParse(json['discounted_unit_price']?.toString() ?? '0') ??
            0.0;
    final int qty = int.tryParse(json['quantity']?.toString() ?? '1') ?? 1;

    return OrderItem(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      productId: int.tryParse(json['product_id']?.toString() ?? '0') ?? 0,
      productName: json['product_name']?.toString() ?? '',
      productImage: json['product_image']?.toString(),
      variantName: json['variant_name']?.toString(),
      subVariantName: json['sub_variant_name']?.toString(),
      discountedUnitPrice: unitPrice,
      lineTotal: double.tryParse(json['line_total']?.toString() ?? '') ??
          (unitPrice * qty),
      quantity: qty,
    );
  }
}
