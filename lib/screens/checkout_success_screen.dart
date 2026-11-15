import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import 'orders_screen.dart';

typedef JsonMap = Map<String, dynamic>;

class CheckoutSuccessScreen extends StatelessWidget {
  final JsonMap orderData;
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

  Future<void> _copyReference(
    BuildContext context,
    String text,
    String label,
  ) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty || cleaned == 'N/A') return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: cleaned));
    HapticFeedback.lightImpact();
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Copied $label: $cleaned'),
        backgroundColor: StorkTheme.primaryDark,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final domain = ApiConfig.resolveBaseDomain(baseUrl);
    final orderNumber = orderData['order_number']?.toString() ?? 'N/A';
    final totalAmount = _formatMoney(orderData['total_amount']);
    final paymentMethod =
        orderData['payment_method']?.toString().toUpperCase() ?? 'COD';
    final List<dynamic> sellerOrders = orderData['seller_orders'] is List
        ? List<dynamic>.from(orderData['seller_orders'] as List)
        : <dynamic>[];

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Order Confirmed'),
        ),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCompletedStepper(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: StorkTheme.borderSubtle),
              boxShadow: StorkTheme.softCardShadow,
            ),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        StorkTheme.success.withValues(alpha: 0.2),
                        StorkTheme.success.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: StorkTheme.success.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: StorkTheme.success,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Thank You! Your Order Has Been Placed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () =>
                      _copyReference(context, orderNumber, 'Order Reference'),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: StorkTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: StorkTheme.borderSubtle),
                    ),
                    child: Column(
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            const Text(
                              'Parent Order Reference:',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  orderNumber,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: StorkTheme.primaryDark,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.copy_rounded,
                                  size: 12,
                                  color: StorkTheme.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            const Text(
                              'Total Order Amount:',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                            Text(
                              '\u20B1$totalAmount ($paymentMethod)',
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
                  ),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final continueBtn = OutlinedButton(
                      onPressed: () {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                      child: const Text(
                        'Continue Shopping',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                    final ordersBtn = ElevatedButton(
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
                      child: const Text(
                        'View My Orders',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );

                    if (constraints.maxWidth < 310) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ordersBtn,
                          const SizedBox(height: 8),
                          continueBtn,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: continueBtn),
                        const SizedBox(width: 10),
                        Expanded(child: ordersBtn),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          if (sellerOrders.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'INDIVIDUAL SELLER ORDERS (${sellerOrders.length})',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: StorkTheme.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            for (final rawSo in sellerOrders)
              if (rawSo is Map)
                _buildSellerOrderCard(
                  context,
                  Map<String, dynamic>.from(rawSo),
                ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCompletedStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 310;
          return Row(
            children: [
              _stepDot('\u2713', 'Cart', done: true, isCompact: isCompact),
              Expanded(child: Container(height: 2, color: StorkTheme.primary)),
              _stepDot('\u2713', 'Order', done: true, isCompact: isCompact),
              Expanded(child: Container(height: 2, color: StorkTheme.primary)),
              _stepDot('\u2713', 'Pay', done: true, isCompact: isCompact),
              Expanded(child: Container(height: 2, color: StorkTheme.primary)),
              _stepDot('4', 'Done', active: true, isCompact: isCompact),
            ],
          );
        },
      ),
    );
  }

  Widget _stepDot(
    String badge,
    String label, {
    bool done = false,
    bool active = false,
    bool isCompact = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isCompact ? 20 : 22,
          height: isCompact ? 20 : 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: active ? StorkTheme.brandGradient : null,
            color: active
                ? null
                : (done
                    ? StorkTheme.primary.withValues(alpha: 0.14)
                    : StorkTheme.surfaceSubtle),
            shape: BoxShape.circle,
          ),
          child: Text(
            badge,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : StorkTheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: isCompact ? 9.5 : 10.5,
            fontWeight: FontWeight.w800,
            color: StorkTheme.primaryDark,
          ),
        ),
      ],
    );
  }

  Widget _buildSellerOrderCard(BuildContext context, JsonMap so) {
    final sellerOrderNo = so['seller_order_number']?.toString() ?? '';
    final storeName =
        so['seller_profile']?['business_name']?.toString() ?? 'Seller Store';
    final statusLabel =
        so['status_label']?.toString() ?? 'Pending Seller Acceptance';
    final payMethod = so['effective_payment_method']?.toString() ??
        so['payment']?['method']?.toString() ??
        'COD';
    final List<dynamic> items = so['items'] is List
        ? List<dynamic>.from(so['items'] as List)
        : <dynamic>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _copyReference(
                        context, sellerOrderNo, 'Seller Order #'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: StorkTheme.brandLight.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sellerOrderNo,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.copy_rounded,
                            size: 10,
                            color: StorkTheme.primaryDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.textMain,
                      ),
                    ),
                  ),
                ],
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
                              fontWeight: FontWeight.w700,
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
                    const SizedBox(width: 8),
                    Text(
                      '\u00D7${rawItem['quantity']} \u2022 \u20B1${_formatMoney(rawItem['line_total'])}',
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Subtotal: \u20B1${_formatMoney(so['subtotal_amount'])} + Ship: \u20B1${_formatMoney(so['shipping_fee'])}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: StorkTheme.textMuted,
                ),
              ),
              Text(
                '\u20B1${_formatMoney(so['total_amount'])} ($payMethod)',
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
