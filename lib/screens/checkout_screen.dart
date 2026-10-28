import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'address_selection_screen.dart';
import '../models/address_model.dart';

class CheckoutScreen extends StatefulWidget {
  final String baseUrl;
  final String token;
  final String mode; // 'cart' or 'buy_now'
  final List<int>? cartIds;
  final Map<String, dynamic>? buyNowData;

  const CheckoutScreen({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.mode,
    this.cartIds,
    this.buyNowData,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;

  Map<String, dynamic>? _checkoutData;
  Address? _selectedAddress;
  String? _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  Future<void> _fetchPreview({int? addressId}) async {
    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> payload = {
        'mode': widget.mode,
      };

      if (addressId != null) payload['address_id'] = addressId;

      if (widget.mode == 'cart' && widget.cartIds != null) {
        payload['cart_ids'] = widget.cartIds;
      } else if (widget.mode == 'buy_now' && widget.buyNowData != null) {
        payload.addAll(widget.buyNowData!);
      }

      final response = await http.post(
        Uri.parse('${widget.baseUrl}/api/v1/checkout/preview'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            _checkoutData = data['data'];
            _idempotencyKey = data['data']['idempotency_key'];
            if (data['data']['selected_address'] != null) {
              _selectedAddress =
                  Address.fromJson(data['data']['selected_address']);
            }
            _isLoading = false;
          });
        }
      } else {
        _showError('Failed to load checkout preview.');
      }
    } catch (e) {
      _showError('Network error occurred.');
    }
  }

  Future<void> _placeOrder() async {
    if (_selectedAddress == null) {
      _showError('Please select a delivery address.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      Map<String, dynamic> payload = {
        'mode': widget.mode,
        'user_address_id': _selectedAddress!.id,
        'idempotency_key': _idempotencyKey,
      };

      if (widget.mode == 'cart' && _checkoutData != null) {
        payload['cart_ids'] = _checkoutData!['cart_ids'];
      } else if (widget.mode == 'buy_now' && widget.buyNowData != null) {
        payload.addAll(widget.buyNowData!);
      }

      final response = await http.post(
        Uri.parse('${widget.baseUrl}/api/v1/checkout/store'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Order placed successfully!'),
                backgroundColor: Color(0xFF10B981)),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        _showError(data['message'] ?? 'Failed to place order.');
      }
    } catch (e) {
      _showError('Network error occurred while placing order.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isSubmitting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE11D48),
      ),
    );
  }

  Future<void> _navigateAndSelectAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddressSelectionScreen(
          baseUrl: widget.baseUrl,
          token: widget.token,
          selectedAddressId: _selectedAddress?.id,
        ),
      ),
    );

    if (result != null && result is Address) {
      if (_selectedAddress?.id != result.id) {
        // Fetch new preview to recalculate shipping based on the new address
        _fetchPreview(addressId: result.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF292524),
        elevation: 0.5,
        title: const Text('Checkout',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFCF4173)))
          : _checkoutData == null
              ? const Center(child: Text('Checkout initialization failed.'))
              : ListView(
                  children: [
                    _buildAddressSection(),
                    const SizedBox(height: 8),
                    ...(_checkoutData!['seller_packages'] as List)
                        .map((pkg) => _buildSellerPackage(pkg)),
                    const SizedBox(height: 8),
                    _buildOrderSummary(),
                    const SizedBox(height: 24),
                  ],
                ),
      bottomNavigationBar: _isLoading || _checkoutData == null
          ? null
          : Container(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Payment',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF78716C))),
                        Text(
                          '₱${_checkoutData!['overall_total'].toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFCF4173),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _placeOrder,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        backgroundColor: const Color(0xFFCF4173),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Place Order',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAddressSection() {
    return GestureDetector(
      onTap: _navigateAndSelectAddress,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: Color(0xFFCF4173), size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: _selectedAddress != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Delivery Address',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF78716C))),
                        const SizedBox(height: 4),
                        Text(
                          '${_selectedAddress!.recipientName} | ${_selectedAddress!.phoneNumber}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF292524)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedAddress!.fullAddress,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF292524)),
                        ),
                      ],
                    )
                  : const Text(
                      'Select a Delivery Address',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE11D48)),
                    ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerPackage(Map<String, dynamic> pkg) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront, size: 20, color: Color(0xFF78716C)),
              const SizedBox(width: 8),
              Text(
                pkg['seller_profile']['business_name'],
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const Divider(height: 24),
          ...(pkg['items'] as List).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item['image_path'] != null
                            ? Image.network(
                                '${widget.baseUrl}/storage/${item['image_path']}',
                                fit: BoxFit.cover)
                            : const Icon(Icons.image, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['product']['name'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFF292524)),
                          ),
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
                                '₱${item['discounted_unit_price'].toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFCF4173)),
                              ),
                              Text('x${item['quantity']}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF78716C))),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              )),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Shipping Fee', style: TextStyle(fontSize: 14)),
              Text('₱${pkg['shipping']['shipping_fee'].toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Order Total', style: TextStyle(fontSize: 14)),
              Text('₱${pkg['total'].toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFCF4173))),
            ],
          ),
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
          const Text('Payment Details',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Payment Method',
                  style: TextStyle(color: Color(0xFF78716C))),
              const Text('Cash on Delivery',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Merchandise Subtotal',
                  style: const TextStyle(color: Color(0xFF78716C))),
              Text('₱${_checkoutData!['overall_subtotal'].toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Shipping Subtotal',
                  style: TextStyle(color: Color(0xFF78716C))),
              Text('₱${_checkoutData!['overall_shipping'].toStringAsFixed(2)}'),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Payment',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('₱${_checkoutData!['overall_total'].toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Color(0xFFCF4173))),
            ],
          ),
        ],
      ),
    );
  }
}
