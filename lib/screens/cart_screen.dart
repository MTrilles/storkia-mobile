import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/cart_model.dart';
import '../providers/global_counters_provider.dart';
import 'checkout_screen.dart';
import 'product_show.dart';

class AnimatedPrice extends ImplicitlyAnimatedWidget {
  final double price;
  final TextStyle? style;
  final String prefix;

  const AnimatedPrice({
    super.key,
    required this.price,
    this.style,
    this.prefix = '₱',
    super.duration = const Duration(milliseconds: 350),
    super.curve = Curves.easeOutCubic,
  });

  @override
  AnimatedWidgetBaseState<AnimatedPrice> createState() => _AnimatedPriceState();
}

class _AnimatedPriceState extends AnimatedWidgetBaseState<AnimatedPrice> {
  Tween<double>? _priceTween;

  String _formatNumber(double val) {
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

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
    final evaluated = _priceTween?.evaluate(animation) ?? 0.0;
    return Text(
      '${widget.prefix}${_formatNumber(evaluated)}',
      style: widget.style,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
}

class CartScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;

  const CartScreen({super.key, required this.baseUrl, required this.token});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _summaryExpanded = false;
  Timer? _autoSyncTimer;

  List<CartItem> _cartItems = [];
  final Map<String, List<CartItem>> _groupedItems = {};

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCartItems();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_isLoading && !_cartItems.any((i) => i.isSyncing)) {
        _fetchCartItems(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchCartItems(silent: true);
    }
  }

  Future<void> _fetchCartItems({bool silent = false}) async {
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/cart'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items =
            data['data'] is List ? data['data'] as List<dynamic> : <dynamic>[];
        final Map<int, bool> previousSelections = {
          for (final item in _cartItems) item.id: item.isSelected
        };

        final List<CartItem> parsed = [];
        for (final e in items) {
          if (e is Map) {
            final cartItem = CartItem.fromJson(Map<String, dynamic>.from(e));
            if (previousSelections.containsKey(cartItem.id)) {
              cartItem.isSelected = previousSelections[cartItem.id]!;
            }
            parsed.add(cartItem);
          }
        }

        setState(() {
          _cartItems = parsed;
          _groupCartItems();
          _isLoading = false;
        });
        ref.read(cartCountProvider.notifier).updateCount(_cartItems.length);
      }
    } catch (_) {
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  void _groupCartItems() {
    _groupedItems.clear();
    for (final item in _cartItems) {
      _groupedItems.putIfAbsent(item.storeName, () => []).add(item);
    }
  }

  List<CartItem> get _selectedItems =>
      _cartItems.where((i) => i.isSelected).toList();

  bool get _isAllSelected =>
      _cartItems.isNotEmpty && _cartItems.every((i) => i.isSelected);

  int get _selectedCount => _selectedItems.length;

  double get _retailTotal =>
      _selectedItems.fold(0.0, (sum, i) => sum + (i.activePrice * i.quantity));

  double get _estimatedTotal => _selectedItems.fold(
      0.0, (sum, i) => sum + (i.discountedPrice * i.quantity));

  double get _savingsTotal => (_retailTotal - _estimatedTotal) > 0
      ? (_retailTotal - _estimatedTotal)
      : 0.0;

  void _toggleAll(bool? val) {
    setState(() {
      for (final item in _cartItems) {
        item.isSelected = val ?? false;
      }
    });
  }

  void _toggleStore(String store, bool? val) {
    setState(() {
      for (final item in (_groupedItems[store] ?? [])) {
        item.isSelected = val ?? false;
      }
    });
  }

  bool _isStoreSelected(String store) {
    final list = _groupedItems[store];
    if (list == null || list.isEmpty) return false;
    return list.every((i) => i.isSelected);
  }

  Future<void> _updateQuantity(CartItem item, int newQty) async {
    if (newQty < 1 || newQty > item.maxStock || item.isSyncing) return;

    final previousQty = item.quantity;
    setState(() {
      item.quantity = newQty;
      item.isSyncing = true;
    });

    try {
      final response = await http
          .put(
            Uri.parse('$_domain/api/v1/cart/${item.id}'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({'quantity': newQty}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      if (response.statusCode != 200) {
        final data = json.decode(response.body);
        setState(() => item.quantity = previousQty);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                data['message']?.toString() ?? 'Unable to update quantity.'),
            backgroundColor: StorkTheme.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => item.quantity = previousQty);
      }
    } finally {
      if (mounted) {
        setState(() => item.isSyncing = false);
      }
    }
  }

  Future<void> _confirmAndRemoveItem(CartItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Remove Item',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          'Remove "${item.product.name}" from your shopping cart?',
          style: const TextStyle(fontSize: 13.5, color: StorkTheme.textMain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: StorkTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StorkTheme.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _cartItems.remove(item);
      _groupCartItems();
    });
    ref.read(cartCountProvider.notifier).updateCount(_cartItems.length);

    try {
      await http.delete(
        Uri.parse('$_domain/api/v1/cart/${item.id}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);
    } catch (_) {
      _fetchCartItems(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text('Shopping Cart (${_cartItems.length})'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : _cartItems.isEmpty
              ? _buildEmptyCart()
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        color: StorkTheme.primary,
                        onRefresh: () => _fetchCartItems(),
                        child: ListView(
                          padding: const EdgeInsets.all(14),
                          children: [
                            _buildStepper(),
                            const SizedBox(height: 12),
                            _buildGlobalMasterCheckbox(),
                            const SizedBox(height: 12),
                            for (final entry in _groupedItems.entries)
                              _buildStoreGroup(entry.key, entry.value),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    _buildBottomCheckoutBar(),
                  ],
                ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: StorkTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: StorkTheme.borderSubtle),
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                size: 36,
                color: StorkTheme.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Shopping Cart is Empty',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: StorkTheme.primaryDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Looks like you haven't added anything to your cart yet.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: StorkTheme.textMuted),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text('Start Shopping'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
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
          ? StorkTheme.primary.withValues(alpha: 0.25)
          : StorkTheme.borderSubtle,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _stepperItem(String step, String label, {bool isActive = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? StorkTheme.primary : StorkTheme.surfaceSubtle,
            shape: BoxShape.circle,
            border:
                isActive ? null : Border.all(color: StorkTheme.borderSubtle),
          ),
          child: Text(
            step,
            style: TextStyle(
              color: isActive ? Colors.white : StorkTheme.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
            color: isActive ? StorkTheme.primary : StorkTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildGlobalMasterCheckbox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _toggleAll(!_isAllSelected),
              child: Row(
                children: [
                  Checkbox(
                    value: _isAllSelected,
                    onChanged: _toggleAll,
                    activeColor: StorkTheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      'ALL ITEMS (${_cartItems.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: StorkTheme.textMain,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            '$_selectedCount of ${_cartItems.length} selected',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: StorkTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreGroup(String storeName, List<CartItem> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: StorkTheme.surfaceSubtle.withValues(alpha: 0.6),
              border: const Border(
                bottom: BorderSide(color: StorkTheme.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _isStoreSelected(storeName),
                  onChanged: (val) => _toggleStore(storeName, val),
                  activeColor: StorkTheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
                const Icon(
                  Icons.storefront_rounded,
                  size: 18,
                  color: StorkTheme.primaryDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    storeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: StorkTheme.primaryDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _buildCartItem(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    final imgUrl = item.imageUrl.isNotEmpty
        ? ApiConfig.storageUrl(item.imageUrl, _domain)
        : '';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Checkbox(
              value: item.isSelected,
              onChanged: (val) =>
                  setState(() => item.isSelected = val ?? false),
              activeColor: StorkTheme.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                StorkRoute.fade(
                  ProductShowScreen(
                    product: item.product,
                    baseUrl: _domain,
                    token: widget.token,
                  ),
                ),
              ).then((_) => _fetchCartItems(silent: true));
            },
            child: Container(
              width: 76,
              height: 76,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: StorkTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StorkTheme.borderSubtle),
              ),
              child: imgUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported_outlined,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                    )
                  : const Icon(Icons.inventory_2_outlined,
                      color: StorkTheme.textMuted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            StorkRoute.fade(
                              ProductShowScreen(
                                product: item.product,
                                baseUrl: _domain,
                                token: widget.token,
                              ),
                            ),
                          ).then((_) => _fetchCartItems(silent: true));
                        },
                        child: Text(
                          item.product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: StorkTheme.textMain,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: StorkTheme.textMuted,
                      ),
                      onPressed: () => _confirmAndRemoveItem(item),
                    ),
                  ],
                ),
                if (item.variantLabel.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: StorkTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: StorkTheme.borderSubtle),
                    ),
                    child: Text(
                      item.variantLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: StorkTheme.textMuted,
                      ),
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
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: item.product.discount > 0
                                  ? StorkTheme.price
                                  : StorkTheme.textMain,
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
                                    fontSize: 10.5,
                                    decoration: TextDecoration.lineThrough,
                                    color: StorkTheme.textMuted,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: StorkTheme.danger
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '-${item.product.discount.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: StorkTheme.danger,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Container(
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border.all(color: StorkTheme.borderSubtle),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_rounded, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: item.quantity > 1 && !item.isSyncing
                                ? () => _updateQuantity(item, item.quantity - 1)
                                : null,
                          ),
                          Container(
                            width: 30,
                            alignment: Alignment.center,
                            child: item.isSyncing
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: StorkTheme.primary,
                                    ),
                                  )
                                : Text(
                                    '${item.quantity}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_rounded, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: item.quantity < item.maxStock &&
                                    !item.isSyncing
                                ? () => _updateQuantity(item, item.quantity + 1)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCheckoutBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        border: const Border(top: BorderSide(color: StorkTheme.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_summaryExpanded) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELECTED ITEMS ($_selectedCount)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_selectedItems.isEmpty)
                    const Text(
                      'No items selected',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: StorkTheme.textMuted,
                      ),
                    )
                  else
                    SizedBox(
                      height: 50,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedItems.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final sel = _selectedItems[index];
                          final thumbUrl = sel.imageUrl.isNotEmpty
                              ? ApiConfig.storageUrl(sel.imageUrl, _domain)
                              : '';
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: StorkTheme.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: StorkTheme.borderSubtle),
                                ),
                                child: thumbUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(9),
                                        child: Image.network(
                                          thumbUrl,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.inventory_2_outlined,
                                        size: 18,
                                        color: StorkTheme.textMuted,
                                      ),
                              ),
                              Positioned(
                                top: -4,
                                right: -4,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => sel.isSelected = false),
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                      color: StorkTheme.textMain,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Retail Price:',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                      AnimatedPrice(
                        price: _retailTotal,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: StorkTheme.textMain,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Promotions / Savings:',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                      AnimatedPrice(
                        prefix: '-₱',
                        price: _savingsTotal,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.price,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                ],
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _summaryExpanded = !_summaryExpanded),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Total: ',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: StorkTheme.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Flexible(
                              child: AnimatedPrice(
                                price: _estimatedTotal,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: _savingsTotal > 0
                                      ? StorkTheme.price
                                      : StorkTheme.textMain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _summaryExpanded
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_up_rounded,
                              size: 20,
                              color: StorkTheme.textMuted,
                            ),
                          ],
                        ),
                        if (_savingsTotal > 0)
                          AnimatedPrice(
                            prefix: 'Saved: ₱',
                            price: _savingsTotal,
                            style: const TextStyle(
                              fontSize: 11,
                              color: StorkTheme.price,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selectedCount == 0
                      ? null
                      : () {
                          final selectedIds =
                              _selectedItems.map((i) => i.id).toList();
                          Navigator.push(
                            context,
                            StorkRoute.fade(
                              CheckoutScreen(
                                baseUrl: _domain,
                                token: widget.token,
                                mode: 'cart',
                                cartIds: selectedIds,
                              ),
                            ),
                          ).then((_) => _fetchCartItems());
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StorkTheme.textMain,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Checkout ($_selectedCount)',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
