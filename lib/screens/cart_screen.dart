import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/cart_model.dart';
import '../providers/global_counters_provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'checkout_screen.dart';
import 'product_show.dart';

typedef JsonMap = Map<String, dynamic>;
typedef CartItemList = List<CartItem>;
typedef CartGroupMap = Map<String, CartItemList>;
typedef SelectionMap = Map<int, bool>;

class AnimatedPrice extends ImplicitlyAnimatedWidget {
  final double price;
  final TextStyle? style;
  final String prefix;

  const AnimatedPrice({
    super.key,
    required this.price,
    this.style,
    this.prefix = '\u20B1',
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

  const CartScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _summaryExpanded = false;
  Timer? _wsDebounceTimer;

  CartItemList _cartItems = [];
  final CartGroupMap _groupedItems = {};

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCartItems();
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'cart' ||
        event.scope == 'catalog' ||
        event.scope == 'marketplace') {
      _wsDebounceTimer?.cancel();
      _wsDebounceTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted && !_isLoading && !_cartItems.any((i) => i.isSyncing)) {
          _fetchCartItems(silent: true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsDebounceTimer?.cancel();
    WebSocketService.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchCartItems(silent: true);
    }
  }

  void _showPopupNotification(
    String message, {
    bool isError = true,
    bool isWarning = false,
  }) {
    if (!mounted || message.trim().isEmpty) return;
    HapticFeedback.heavyImpact();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : (isWarning
                      ? Icons.info_outline_rounded
                      : Icons.check_circle_outline_rounded),
              color: Colors.white,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.trim(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        backgroundColor: isError
            ? StorkTheme.danger
            : (isWarning ? const Color(0xFFB45309) : StorkTheme.success),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  List<dynamic> _extractCartItemsList(dynamic raw) {
    if (raw is List) return List<dynamic>.from(raw);
    if (raw is Map) {
      for (final key in ['items', 'cart_items', 'cart', 'data']) {
        if (raw.containsKey(key) && raw[key] != null && raw[key] != raw) {
          final extracted = _extractCartItemsList(raw[key]);
          if (extracted.isNotEmpty) return extracted;
        }
      }
    }
    return <dynamic>[];
  }

  Future<void> _fetchCartItems({bool silent = false}) async {
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('$_domain/api/v1/cart'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = _extractCartItemsList(
          data is Map ? (data['data'] ?? data) : data,
        );

        final SelectionMap previousSelections = {
          for (final item in _cartItems) item.id: item.isSelected
        };

        final CartItemList parsed = [];
        for (final e in items) {
          if (e is Map) {
            final cartItem = CartItem.fromJson(JsonMap.from(e));
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
      } else if (!silent) {
        _showPopupNotification('Failed to load shopping cart items.');
      }
    } catch (_) {
      if (mounted && !silent) {
        _showPopupNotification(
            'Network error occurred while loading your cart.');
      }
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

  CartItemList get _selectedItems =>
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
    HapticFeedback.selectionClick();
    setState(() {
      for (final item in _cartItems) {
        item.isSelected = val ?? false;
      }
    });
  }

  void _toggleStore(String store, bool? val) {
    HapticFeedback.selectionClick();
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
    if (item.isSyncing) return;
    if (newQty < 1) {
      _showPopupNotification(
        'Minimum quantity is 1. Tap the trash icon to remove "${item.product.name}".',
        isError: false,
        isWarning: true,
      );
      return;
    }
    if (newQty > item.maxStock) {
      _showPopupNotification(
        'Maximum available stock (${item.maxStock}) reached for "${item.product.name}".',
        isError: true,
      );
      return;
    }

    HapticFeedback.lightImpact();

    final previousQty = item.quantity;
    setState(() {
      item.quantity = newQty;
      item.isSyncing = true;
    });

    try {
      final response = await ApiService.httpClient
          .put(
            Uri.parse('$_domain/api/v1/cart/${item.id}'),
            headers: ApiService.buildHeaders(widget.token, isJson: true),
            body: json.encode({'quantity': newQty}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode != 200) {
        final data = json.decode(response.body);
        setState(() => item.quantity = previousQty);
        _showPopupNotification(
          data is Map
              ? (data['message']?.toString() ??
                  data['error']?.toString() ??
                  'Unable to update quantity.')
              : 'Unable to update quantity.',
          isError: true,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => item.quantity = previousQty);
        _showPopupNotification(
          'Network error while updating item quantity.',
          isError: true,
        );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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

    HapticFeedback.mediumImpact();
    setState(() {
      _cartItems.remove(item);
      _groupCartItems();
    });
    ref.read(cartCountProvider.notifier).updateCount(_cartItems.length);

    try {
      await ApiService.httpClient
          .delete(
            Uri.parse('$_domain/api/v1/cart/${item.id}'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);
    } catch (_) {
      _fetchCartItems(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Shopping Cart (${_cartItems.length})'),
        ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: StorkTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                size: 40,
                color: StorkTheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Shopping Cart is Empty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: StorkTheme.primaryDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Looks like you haven't added anything to your cart yet. Discover curated deals and verified stores!",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: StorkTheme.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: const Text('Start Shopping'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper() {
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
              _stepperItem('1', 'Cart', isActive: true, isCompact: isCompact),
              Expanded(child: _buildStepDivider(isActive: true)),
              _stepperItem('2', 'Order', isCompact: isCompact),
              Expanded(child: _buildStepDivider()),
              _stepperItem('3', 'Pay', isCompact: isCompact),
              Expanded(child: _buildStepDivider()),
              _stepperItem('4', 'Done', isCompact: isCompact),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStepDivider({bool isActive = false}) {
    return Container(
      height: 2,
      color: isActive
          ? StorkTheme.primary.withValues(alpha: 0.35)
          : StorkTheme.borderSubtle,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _stepperItem(
    String step,
    String label, {
    bool isActive = false,
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
            gradient: isActive ? StorkTheme.brandGradient : null,
            color: isActive ? null : StorkTheme.surfaceSubtle,
            shape: BoxShape.circle,
            border:
                isActive ? null : Border.all(color: StorkTheme.borderSubtle),
          ),
          child: Text(
            step,
            style: TextStyle(
              color: isActive ? Colors.white : StorkTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: isCompact ? 9.5 : 10.5,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? StorkTheme.primaryDark : StorkTheme.textMuted,
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _toggleAll(!_isAllSelected),
              borderRadius: BorderRadius.circular(12),
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
                        fontSize: 12.5,
                        color: StorkTheme.primaryDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: StorkTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_selectedCount of ${_cartItems.length} selected',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: StorkTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreGroup(String storeName, CartItemList items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: StorkTheme.surfaceSubtle.withValues(alpha: 0.7),
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
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: StorkTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    size: 16,
                    color: StorkTheme.primaryDark,
                  ),
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
    final isCompact = MediaQuery.sizeOf(context).width < 360;
    final thumbSize = isCompact ? 64.0 : 76.0;

    return Padding(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: isCompact ? 12 : 18),
            child: SizedBox(
              width: 32,
              child: Checkbox(
                value: item.isSelected,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  setState(() => item.isSelected = val ?? false);
                },
                activeColor: StorkTheme.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(width: 4),
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
              width: thumbSize,
              height: thumbSize,
              margin: EdgeInsets.only(right: isCompact ? 10 : 12),
              decoration: BoxDecoration(
                color: StorkTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: StorkTheme.borderSubtle),
              ),
              child: imgUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported_outlined,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.inventory_2_outlined,
                      color: StorkTheme.textMuted,
                    ),
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
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: StorkTheme.borderSubtle),
                    ),
                    child: Text(
                      item.variantLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedPrice(
                          price: item.discountedPrice * item.quantity,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: item.product.discount > 0
                                ? StorkTheme.price
                                : StorkTheme.primary,
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
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color:
                                      StorkTheme.danger.withValues(alpha: 0.1),
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
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: StorkTheme.surfaceSubtle,
                        border: Border.all(color: StorkTheme.borderSubtle),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.remove_rounded,
                              size: 15,
                              color: item.quantity > 1
                                  ? StorkTheme.textMain
                                  : StorkTheme.textMuted,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: item.isSyncing
                                ? null
                                : () =>
                                    _updateQuantity(item, item.quantity - 1),
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
                            icon: Icon(
                              Icons.add_rounded,
                              size: 15,
                              color: item.quantity < item.maxStock
                                  ? StorkTheme.textMain
                                  : StorkTheme.textMuted,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: item.isSyncing
                                ? null
                                : () =>
                                    _updateQuantity(item, item.quantity + 1),
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
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            if (_selectedCount == 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: StorkTheme.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: StorkTheme.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Color(0xFF92400E),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Incomplete Step: Select at least 1 cart item to enable Checkout.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_summaryExpanded)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: screenHeight * 0.35),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECTED ITEMS ($_selectedCount)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
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
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
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
                                            borderRadius:
                                                BorderRadius.circular(9),
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
                                      onTap: () => setState(
                                          () => sel.isSelected = false),
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
                            prefix: '-\u20B1',
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
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _summaryExpanded = !_summaryExpanded);
                    },
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
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w900,
                                  color: _savingsTotal > 0
                                      ? StorkTheme.price
                                      : StorkTheme.primaryDark,
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
                            prefix: 'Saved: \u20B1',
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
                const SizedBox(width: 10),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient:
                        _selectedCount > 0 ? StorkTheme.brandGradient : null,
                    color: _selectedCount > 0 ? null : StorkTheme.surfaceSubtle,
                    borderRadius: BorderRadius.circular(14),
                    border: _selectedCount > 0
                        ? null
                        : Border.all(color: StorkTheme.borderSubtle),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      if (_selectedCount == 0) {
                        _showPopupNotification(
                          'Incomplete Step: Please select at least 1 item in your cart to proceed to checkout.',
                          isError: true,
                        );
                        return;
                      }
                      HapticFeedback.mediumImpact();
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
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: _selectedCount > 0
                          ? Colors.white
                          : StorkTheme.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Checkout ($_selectedCount)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
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
