import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_model.dart';

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
      quantity: json['quantity'] ?? 1,
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

class AnimatedPrice extends ImplicitlyAnimatedWidget {
  final double price;
  final TextStyle? style;
  final String prefix;

  const AnimatedPrice({
    super.key,
    required this.price,
    this.style,
    this.prefix = '₱',
    super.duration = const Duration(milliseconds: 400),
    super.curve = Curves.easeOutCubic,
  });

  @override
  AnimatedWidgetBaseState<AnimatedPrice> createState() => _AnimatedPriceState();
}

class _AnimatedPriceState extends AnimatedWidgetBaseState<AnimatedPrice> {
  Tween<double>? _priceTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _priceTween = visitor(
      _priceTween,
      widget.price,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${widget.prefix}${_priceTween?.evaluate(animation).toStringAsFixed(2) ?? '0.00'}',
      style: widget.style,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
}

class CartScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const CartScreen({super.key, required this.baseUrl, required this.token});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isLoading = true;
  List<CartItem> _cartItems = [];
  Map<String, List<CartItem>> _groupedItems = {};

  @override
  void initState() {
    super.initState();
    _fetchCartItems();
  }

  Future<void> _fetchCartItems() async {
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/v1/cart'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List items = data['data'] ?? [];
        _cartItems = items.map((e) => CartItem.fromJson(e)).toList();
        _groupCartItems();
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _groupCartItems() {
    _groupedItems.clear();
    for (var item in _cartItems) {
      if (!_groupedItems.containsKey(item.storeName)) {
        _groupedItems[item.storeName] = [];
      }
      _groupedItems[item.storeName]!.add(item);
    }
  }

  bool get _isAllSelected =>
      _cartItems.isNotEmpty && _cartItems.every((i) => i.isSelected);

  // Changed to count items instead of quantities to fix "10 of 2 selected" issue
  int get _selectedCount => _cartItems.where((i) => i.isSelected).length;

  double get _retailTotal => _cartItems
      .where((i) => i.isSelected)
      .fold(0, (sum, i) => sum + (i.activePrice * i.quantity));

  double get _estimatedTotal => _cartItems
      .where((i) => i.isSelected)
      .fold(0, (sum, i) => sum + (i.discountedPrice * i.quantity));

  double get _savingsTotal => _retailTotal - _estimatedTotal;

  void _toggleAll(bool? val) {
    setState(() {
      for (var item in _cartItems) {
        item.isSelected = val ?? false;
      }
    });
  }

  void _toggleStore(String store, bool? val) {
    setState(() {
      for (var item in _groupedItems[store]!) {
        item.isSelected = val ?? false;
      }
    });
  }

  bool _isStoreSelected(String store) {
    if (_groupedItems[store] == null || _groupedItems[store]!.isEmpty)
      return false;
    return _groupedItems[store]!.every((i) => i.isSelected);
  }

  Future<void> _updateQuantity(CartItem item, int newQty) async {
    if (newQty < 1 || newQty > item.maxStock || item.isSyncing) return;

    setState(() {
      item.quantity = newQty;
      item.isSyncing = true;
    });

    try {
      await http.put(
        Uri.parse('${widget.baseUrl}/api/v1/cart/${item.id}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode({'quantity': newQty}),
      );
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) {
        setState(() => item.isSyncing = false);
      }
    }
  }

  Future<void> _removeItem(CartItem item) async {
    setState(() {
      _cartItems.remove(item);
      _groupCartItems();
    });
    try {
      await http.delete(
        Uri.parse('${widget.baseUrl}/api/v1/cart/${item.id}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF292524),
        title: const Text('Shopping Cart',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFCF4173)))
          : _cartItems.isEmpty
              ? _buildEmptyCart()
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _buildStepper(),
                          const SizedBox(height: 12),
                          _buildGlobalMasterCheckbox(),
                          const SizedBox(height: 12),
                          ..._groupedItems.entries
                              .map((entry) =>
                                  _buildStoreGroup(entry.key, entry.value))
                              .toList(),
                        ],
                      ),
                    ),
                    _buildBottomCheckoutBar(),
                  ],
                ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined,
              size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('Your Shopping Cart is Empty',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF292524))),
          const SizedBox(height: 8),
          const Text('Looks like you haven\'t added anything yet.',
              style: TextStyle(color: Color(0xFF78716C))),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCF4173),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text('Start Shopping',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          _stepperItem('1', 'Cart', isActive: true),
          Expanded(child: _buildStepDivider(isActive: true)),
          _stepperItem('2', 'Place Order'),
          Expanded(child: _buildStepDivider()),
          _stepperItem('3', 'Pay'),
          Expanded(child: _buildStepDivider()),
          _stepperItem('4', 'Complete'),
        ],
      ),
    );
  }

  Widget _buildStepDivider({bool isActive = false}) {
    return Container(
      height: 2,
      color: isActive
          ? const Color(0xFFCF4173).withOpacity(0.2)
          : Colors.grey.shade200,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _stepperItem(String step, String label, {bool isActive = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFCF4173) : Colors.grey.shade100,
            shape: BoxShape.circle,
            border: isActive ? null : Border.all(color: Colors.grey.shade300),
          ),
          child: Text(step,
              style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey.shade500,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? const Color(0xFFCF4173) : Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildGlobalMasterCheckbox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Checkbox(
                  value: _isAllSelected,
                  onChanged: _toggleAll,
                  activeColor: const Color(0xFFCF4173),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Text(
                    'ALL ITEMS (${_cartItems.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$_selectedCount of ${_cartItems.length} selected',
            style: const TextStyle(fontSize: 11, color: Color(0xFF78716C)),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreGroup(String storeName, List<CartItem> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFF5F5F4).withOpacity(0.5),
                border:
                    Border(bottom: BorderSide(color: Colors.grey.shade200))),
            child: Row(
              children: [
                Checkbox(
                  value: _isStoreSelected(storeName),
                  onChanged: (val) => _toggleStore(storeName, val),
                  activeColor: const Color(0xFFCF4173),
                  visualDensity: VisualDensity.compact,
                ),
                const Icon(Icons.storefront,
                    size: 18, color: Color(0xFF78716C)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    storeName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF292524)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          ...items.map((item) => _buildCartItem(item)).toList(),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.isSelected,
            onChanged: (val) => setState(() => item.isSelected = val ?? false),
            activeColor: const Color(0xFFCF4173),
            visualDensity: VisualDensity.compact,
          ),
          Container(
            width: 72,
            height: 72,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: item.imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                        '${widget.baseUrl}/storage/${item.imageUrl}',
                        fit: BoxFit.cover))
                : const Icon(Icons.image, color: Colors.grey),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            height: 1.2),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: Color(0xFF78716C)),
                        onPressed: () => _removeItem(item),
                      ),
                    ),
                  ],
                ),
                if (item.variant != null || item.subVariant != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2, bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F4),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: Text(
                      [item.variant, item.subVariant]
                          .where((e) => e != null && e.isNotEmpty)
                          .join(' / '),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF78716C)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedPrice(
                            price: item.discountedPrice * item.quantity,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: item.product.discount > 0
                                  ? const Color(0xFFCF4173)
                                  : const Color(0xFF292524),
                            ),
                          ),
                          if (item.product.discount > 0)
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 4,
                              children: [
                                AnimatedPrice(
                                  price: item.activePrice * item.quantity,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      decoration: TextDecoration.lineThrough,
                                      color: Color(0xFF78716C)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      border: Border.all(
                                          color: Colors.red.shade200),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Text(
                                      '-${item.product.discount.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red)),
                                )
                              ],
                            ),
                        ],
                      ),
                    ),
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            onPressed: item.quantity > 1 && !item.isSyncing
                                ? () => _updateQuantity(item, item.quantity - 1)
                                : null,
                          ),
                          Container(
                            width: 28,
                            alignment: Alignment.center,
                            child: item.isSyncing
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFCF4173)))
                                : Text('${item.quantity}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            onPressed: item.quantity < item.maxStock &&
                                    !item.isSyncing
                                ? () => _updateQuantity(item, item.quantity + 1)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBottomCheckoutBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Total: ',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF78716C),
                              fontWeight: FontWeight.bold)),
                      Expanded(
                        child: AnimatedPrice(
                          price: _estimatedTotal,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _savingsTotal > 0
                                ? const Color(0xFFCF4173)
                                : const Color(0xFF292524),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_savingsTotal > 0)
                    AnimatedPrice(
                      prefix: 'Saved: ₱',
                      price: _savingsTotal,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFCF4173),
                          fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _selectedCount == 0 ? null : () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCF4173),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Checkout ($_selectedCount)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}
