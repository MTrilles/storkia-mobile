import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import 'orders_screen.dart';

class CheckoutSuccessScreen extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final String baseUrl;
  final String token;

  const CheckoutSuccessScreen({
    super.key,
    required this.orderData,
    required this.baseUrl,
    required this.token,
  });

  String _formatMoney(dynamic raw) {
    final val = double.tryParse(raw?.toString() ?? '0') ?? 0.0;
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final domain = ApiConfig.resolveBaseDomain(baseUrl);
    final orderNumber = orderData['order_number']?.toString() ?? 'N/A';
    final totalAmount = _formatMoney(orderData['total_amount']);
    final paymentMethod =
        orderData['payment_method']?.toString().toUpperCase() ?? 'COD';
    final List sellerOrders = orderData['seller_orders'] is List
        ? (orderData['seller_orders'] as List)
        : [];

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Order Confirmed'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCompletedStepper(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: StorkTheme.borderSubtle),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: StorkTheme.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: StorkTheme.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: StorkTheme.success,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Thank You! Your Order Has Been Placed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 13,
                      color: StorkTheme.textMuted,
                      height: 1.45,
                    ),
                    children: [
                      const TextSpan(text: 'Parent Order Reference: '),
                      TextSpan(
                        text: orderNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.textMain,
                        ),
                      ),
                      const TextSpan(text: '\nTotal Order Amount: '),
                      TextSpan(
                        text: '₱$totalAmount ($paymentMethod)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);
                        },
                        child: const Text('Continue Shopping'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);
                          Navigator.push(
                            context,
                            StorkRoute.fade(
                              OrdersScreen(
                                baseUrl: domain,
                                token: token,
                              ),
                            ),
                          );
                        },
                        child: const Text('View My Orders'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (sellerOrders.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'INDIVIDUAL SELLER ORDERS (${sellerOrders.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: StorkTheme.textMuted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            for (final rawSo in sellerOrders)
              if (rawSo is Map)
                _buildSellerOrderCard(Map<String, dynamic>.from(rawSo)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCompletedStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      child: Row(
        children: [
          _stepDot('✓', 'Cart', done: true),
          Expanded(child: Container(height: 2, color: StorkTheme.primary)),
          _stepDot('✓', 'Order', done: true),
          Expanded(child: Container(height: 2, color: StorkTheme.primary)),
          _stepDot('✓', 'Pay', done: true),
          Expanded(child: Container(height: 2, color: StorkTheme.primary)),
          _stepDot('4', 'Complete', active: true),
        ],
      ),
    );
  }

  Widget _stepDot(String badge, String label,
      {bool done = false, bool active = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? StorkTheme.primary
                : StorkTheme.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Text(
            badge,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : StorkTheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: StorkTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildSellerOrderCard(Map<String, dynamic> so) {
    final sellerOrderNo = so['seller_order_number']?.toString() ?? '';
    final storeName =
        so['seller_profile']?['business_name']?.toString() ?? 'Seller Store';
    final statusLabel =
        so['status_label']?.toString() ?? 'Pending Seller Acceptance';
    final payMethod = so['effective_payment_method']?.toString() ??
        so['payment']?['method']?.toString() ??
        'COD';
    final List items = so['items'] is List ? (so['items'] as List) : [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: StorkTheme.brandLight.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        sellerOrderNo,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
                        ),
                      ),
                    ),
                    Text(
                      storeName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.textMain,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: StorkTheme.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          for (final rawItem in items)
            if (rawItem is Map)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rawItem['product_name']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: StorkTheme.textMain,
                            ),
                          ),
                          if (rawItem['variant_name'] != null)
                            Text(
                              [
                                rawItem['variant_name'],
                                rawItem['sub_variant_name']
                              ]
                                  .where((e) =>
                                      e != null && e.toString().isNotEmpty)
                                  .join(' / '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '×${rawItem['quantity']}  ₱${_formatMoney(rawItem['line_total'])}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.textMain,
                      ),
                    ),
                  ],
                ),
              ),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal: ₱${_formatMoney(so['subtotal_amount'])} + Ship: ₱${_formatMoney(so['shipping_fee'])}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: StorkTheme.textMuted,
                ),
              ),
              Text(
                '₱${_formatMoney(so['total_amount'])} ($payMethod)',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: StorkTheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
