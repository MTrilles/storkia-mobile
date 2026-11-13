import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../providers/global_counters_provider.dart';
import '../providers/wishlist_provider.dart';
import '../services/api_service.dart';
import 'cart_screen.dart';
import 'product_show.dart';

class WishlistScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;

  const WishlistScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen>
    with WidgetsBindingObserver {
  Timer? _autoSyncTimer;
  int? _addingProductId;
  String _selectedFilter = 'all';

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(wishlistProvider.notifier)
          .fetchWishlist(_domain, widget.token, silent: false);
    });
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      ref
          .read(wishlistProvider.notifier)
          .fetchWishlist(_domain, widget.token, silent: true);
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
      ref
          .read(wishlistProvider.notifier)
          .fetchWishlist(_domain, widget.token, silent: true);
    }
  }

  String _formatMoney(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  bool _hasActiveVariants(Product product) {
    final vars = product.variants;
    if (vars == null || vars['items'] is! List) return false;
    final items = vars['items'] as List;
    return items.any(
      (i) =>
          i is Map &&
          i['is_archived'] != true &&
          (i['status'] ?? 'Approved').toString() == 'Approved',
    );
  }

  Future<void> _handleAddToCart(Product product) async {
    if (product.isUnavailable ||
        product.isSoldOut ||
        product.isStoreOnVacation) {
      return;
    }

    if (_hasActiveVariants(product)) {
      Navigator.push(
        context,
        StorkRoute.fade(
          ProductShowScreen(
            product: product,
            baseUrl: _domain,
            token: widget.token,
          ),
        ),
      ).then((_) {
        ref
            .read(wishlistProvider.notifier)
            .fetchWishlist(_domain, widget.token, silent: true);
      });
      return;
    }

    setState(() => _addingProductId = product.id);
    final res = await ApiService.addToCart(
      token: widget.token,
      productId: product.id,
      quantity: 1,
    );
    if (!mounted) return;
    setState(() => _addingProductId = null);

    if (res['success'] == true) {
      ref.read(cartCountProvider.notifier).fetchCartCount(widget.token);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${product.name}" to your cart!'),
          backgroundColor: StorkTheme.success,
          action: SnackBarAction(
            label: 'VIEW CART',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                StorkRoute.fade(
                  CartScreen(baseUrl: _domain, token: widget.token),
                ),
              );
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['message']?.toString() ?? 'Unable to add item to cart.',
          ),
          backgroundColor: StorkTheme.danger,
        ),
      );
    }
  }

  Future<void> _removeItem(Product product) async {
    final removed = await ref
        .read(wishlistProvider.notifier)
        .removeFromWishlist(_domain, widget.token, product.id);
    if (!mounted) return;
    if (removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${product.name}" from your wishlist.'),
          backgroundColor: StorkTheme.textMain,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlistState = ref.watch(wishlistProvider);
    final allItems = wishlistState.items;

    final List<Product> visibleItems = allItems.where((p) {
      if (_selectedFilter == 'available') {
        return !p.isUnavailable && !p.isSoldOut && !p.isStoreOnVacation;
      }
      if (_selectedFilter == 'promos') {
        return p.effectiveDiscountPercent > 0;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text('My Wish List (${allItems.length})'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                StorkRoute.fade(
                  CartScreen(baseUrl: _domain, token: widget.token),
                ),
              );
            },
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
        ],
      ),
      body: wishlistState.isLoading && allItems.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => ref
                  .read(wishlistProvider.notifier)
                  .fetchWishlist(_domain, widget.token, silent: true),
              child: allItems.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(32),
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: StorkTheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite_border_rounded,
                              size: 38,
                              color: StorkTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Your Wish List Is Empty',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tap the heart icon on any product to save it here and track price drops or restocks.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: StorkTheme.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: const BoxDecoration(
                            color: StorkTheme.surface,
                            border: Border(
                              bottom:
                                  BorderSide(color: StorkTheme.borderSubtle),
                            ),
                          ),
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _buildFilterChip(
                                  'all', 'All Saved (${allItems.length})'),
                              const SizedBox(width: 8),
                              _buildFilterChip('available', 'In Stock Only'),
                              const SizedBox(width: 8),
                              _buildFilterChip('promos', 'On Sale / Promo'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: visibleItems.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No wishlisted items match this filter.',
                                    style:
                                        TextStyle(color: StorkTheme.textMuted),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(14),
                                  itemCount: visibleItems.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final product = visibleItems[index];
                                    return _buildWishlistCard(product);
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final active = _selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active ? StorkTheme.brandGradient : null,
          color: active ? null : StorkTheme.surfaceSubtle,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? StorkTheme.primary : StorkTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: active ? Colors.white : StorkTheme.textMain,
          ),
        ),
      ),
    );
  }

  Widget _buildWishlistCard(Product product) {
    final String imgUrl = product.pictures.isNotEmpty
        ? ApiConfig.storageUrl(product.pictures.first, _domain)
        : '';
    final String storeName =
        product.sellerProfile?.businessName ?? 'Verified Store';
    final bool isDisabled =
        product.isUnavailable || product.isSoldOut || product.isStoreOnVacation;

    String? statusBadge;
    if (product.isUnavailable) {
      statusBadge = 'UNAVAILABLE';
    } else if (product.isStoreOnVacation) {
      statusBadge = 'STORE ON VACATION';
    } else if (product.isSoldOut) {
      statusBadge = 'SOLD OUT';
    }

    return GestureDetector(
      onTap: () {
        if (product.isUnavailable) return;
        Navigator.push(
          context,
          StorkRoute.fade(
            ProductShowScreen(
              product: product,
              baseUrl: _domain,
              token: widget.token,
            ),
          ),
        ).then((_) {
          ref
              .read(wishlistProvider.notifier)
              .fetchWishlist(_domain, widget.token, silent: true);
        });
      },
      child: Opacity(
        opacity: isDisabled ? 0.68 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StorkTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: StorkTheme.borderSubtle),
            boxShadow: StorkTheme.softCardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 88,
                      height: 88,
                      color: StorkTheme.surfaceSubtle,
                      child: imgUrl.isNotEmpty
                          ? Image.network(
                              imgUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.inventory_2_outlined,
                                color: StorkTheme.textMuted,
                              ),
                            )
                          : const Icon(
                              Icons.inventory_2_outlined,
                              color: StorkTheme.textMuted,
                            ),
                    ),
                  ),
                  if (statusBadge != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(14),
                          ),
                        ),
                        child: Text(
                          statusBadge,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.storefront_rounded,
                                    size: 12,
                                    color: StorkTheme.textMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      storeName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: StorkTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                product.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.textMain,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () => _removeItem(product),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: StorkTheme.danger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '₱${_formatMoney(product.discountedPrice)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: StorkTheme.price,
                              ),
                            ),
                            if (product.effectiveDiscountPercent > 0)
                              Text(
                                '₱${_formatMoney(product.price)} (-${product.effectiveDiscountPercent.toStringAsFixed(0)}%)',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  decoration: TextDecoration.lineThrough,
                                  color: StorkTheme.textMuted,
                                ),
                              ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed:
                              (isDisabled || _addingProductId == product.id)
                                  ? null
                                  : () => _handleAddToCart(product),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 34),
                          ),
                          icon: _addingProductId == product.id
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _hasActiveVariants(product)
                                      ? Icons.tune_rounded
                                      : Icons.add_shopping_cart_rounded,
                                  size: 15,
                                ),
                          label: Text(
                            isDisabled
                                ? (statusBadge ?? 'Unavailable')
                                : (_hasActiveVariants(product)
                                    ? 'Select Option'
                                    : 'Add to Cart'),
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
