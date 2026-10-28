import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class OrderDetailsScreen extends StatefulWidget {
  final int orderId;
  final String baseUrl;
  final String token;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _orderData;

  @override
  void initState() {
    super.initState();
    _fetchOrderDetails();
  }

  Future<void> _fetchOrderDetails() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/v1/orders/${widget.orderId}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            _orderData = data['data'];
            _isLoading = false;
          });
        }
      } else {
        _showError('Failed to load order details.');
      }
    } catch (e) {
      _showError('Network error occurred.');
    }
  }

  Future<void> _confirmReceipt() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Receipt'),
        content: const Text(
            'Are you sure you have received the items in good condition? This will release the payment to the seller and complete the order.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF78716C))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCF4173)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _showLoadingDialog();

    try {
      final response = await http.post(
        Uri.parse(
            '${widget.baseUrl}/api/v1/orders/${widget.orderId}/confirm-receipt'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success']) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Order completed successfully!'),
            backgroundColor: Color(0xFF10B981)));
        _fetchOrderDetails();
      } else {
        _showError(data['message'] ?? 'Failed to confirm receipt.');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Network error.');
    }
  }

  Future<void> _reportDispute() async {
    final TextEditingController reasonController = TextEditingController();
    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report an Issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Please describe the issue with your delivery (minimum 10 characters):',
                style: TextStyle(fontSize: 13, color: Color(0xFF78716C))),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g., Damaged item, missing parts, wrong variant...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF78716C))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (submit != true) return;

    final reason = reasonController.text.trim();
    if (reason.length < 10) {
      _showError('Reason must be at least 10 characters.');
      return;
    }

    _showLoadingDialog();

    try {
      final response = await http.post(
        Uri.parse(
            '${widget.baseUrl}/api/v1/orders/${widget.orderId}/report-dispute'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode({'dispute_reason': reason}),
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success']) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Dispute reported successfully.'),
            backgroundColor: Color(0xFFE11D48)));
        _fetchOrderDetails();
      } else {
        _showError(data['message'] ?? 'Failed to report dispute.');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Network error.');
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFCF4173))),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: const Color(0xFFE11D48)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          backgroundColor: Color(0xFFF5F5F4),
          body: Center(
              child: CircularProgressIndicator(color: Color(0xFFCF4173))));
    }

    if (_orderData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Details')),
        body: const Center(child: Text('Order not found.')),
      );
    }

    final status = _orderData!['status'] ?? 'pending';
    final isDelivered = status == 'delivered';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF292524),
        elevation: 0.5,
        title: const Text('Order Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(status),
            const SizedBox(height: 8),
            _buildDeliveryAddress(),
            const SizedBox(height: 8),
            _buildOrderItems(),
            const SizedBox(height: 8),
            _buildOrderSummary(),
            const SizedBox(height: 8),
            _buildOrderMeta(),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: isDelivered ? _buildActionBottomBar() : null,
    );
  }

  Widget _buildStatusBanner(String status) {
    final readableStatus = status.replaceAll('_', ' ').toUpperCase();
    return Container(
      width: double.infinity,
      color: const Color(0xFFCF4173),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(readableStatus,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Thank you for shopping with Storkia!',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildDeliveryAddress() {
    final address = _orderData!['delivery_address_snapshot'] ?? {};
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on, color: Color(0xFFCF4173), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivery Address',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                    '${address['recipient_name'] ?? ''} | ${address['phone_number'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF292524))),
                const SizedBox(height: 4),
                Text(address['full_address'] ?? 'No address provided',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF78716C))),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildOrderItems() {
    final items = _orderData!['items'] as List? ?? [];
    final seller = _orderData!['seller_profile'] ?? {};

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.storefront,
                    size: 18, color: Color(0xFF78716C)),
                const SizedBox(width: 8),
                Text(seller['business_name'] ?? 'Store',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item['product_image'] != null
                            ? Image.network(
                                '${widget.baseUrl}/storage/${item['product_image']}',
                                fit: BoxFit.cover)
                            : const Icon(Icons.image, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['product_name'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(height: 4),
                          if (item['variant_name'] != null)
                            Text(
                              '${item['variant_name']}${item['sub_variant_name'] != null ? ' - ${item['sub_variant_name']}' : ''}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF78716C)),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '₱${double.tryParse(item['discounted_unit_price'].toString())?.toStringAsFixed(2) ?? '0.00'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFCF4173)),
                              ),
                              Text('x${item['quantity']}',
                                  style: const TextStyle(
                                      fontSize: 13, color: Color(0xFF78716C))),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Items', style: TextStyle(fontSize: 14)),
                Text('${items.length}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Merchandise Subtotal',
                  style: TextStyle(color: Color(0xFF78716C), fontSize: 13)),
              Text(
                  '₱${double.tryParse(_orderData!['subtotal_amount'].toString())?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Shipping Fee',
                  style: TextStyle(color: Color(0xFF78716C), fontSize: 13)),
              Text(
                  '₱${double.tryParse(_orderData!['shipping_fee'].toString())?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Order Total',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(
                '₱${double.tryParse(_orderData!['total_amount'].toString())?.toStringAsFixed(2) ?? '0.00'}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFFCF4173)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderMeta() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Order Number',
                  style: TextStyle(color: Color(0xFF78716C), fontSize: 13)),
              Text(_orderData!['seller_order_number'] ?? '',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Time Placed',
                  style: TextStyle(color: Color(0xFF78716C), fontSize: 13)),
              Text(_orderData!['created_at'] ?? '',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _reportDispute,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: const Color(0xFFE11D48),
                  side: const BorderSide(color: Color(0xFFE11D48)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Return / Refund',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _confirmReceipt,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFFCF4173),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Confirm Receipt',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
