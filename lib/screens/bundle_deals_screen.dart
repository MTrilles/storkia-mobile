import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../providers/global_counters_provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'cart_screen.dart';
import 'product_show.dart';

typedef JsonMap = Map<String, dynamic>;

class BundleDealsScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;

  const BundleDealsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<BundleDealsScreen> createState() => _BundleDealsScreenState();
}

class _BundleDealsScreenState extends ConsumerState<BundleDealsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  int? _addingBundleId;
  List<JsonMap> _bundles = [];

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchBundles();
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'marketplace' ||
        event.scope == 'catalog' ||
        event.scope == 'general') {
      _fetchBundles(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WebSocketService.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchBundles(silent: true);
    }
  }

  String _formatMoney(dynamic raw) {
    final val = double.tryParse(raw?.toString() ?? '0') ?? 0.0;
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  List<JsonMap> _extractBundlesList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) JsonMap.from(item),
      ];
    }
    if (raw is Map) {
      for (final key in [
        'bundles',
        'bundle_deals',
        'items',
        'deals',
        'data',
      ]) {
        if (raw.containsKey(key) && raw[key] != null && raw[key] != raw) {
          final extracted = _extractBundlesList(raw[key]);
          if (extracted.isNotEmpty) return extracted;
        }
      }
      for (final value in raw.values) {
        if (value is List) {
          final extracted = _extractBundlesList(value);
          if (extracted.isNotEmpty) return extracted;
        }
      }
    }
    return [];
  }

  Future<void> _fetchBundles({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('$_domain/api/v1/bundles'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final parsed =
            _extractBundlesList(body is Map ? (body['data'] ?? body) : body);
        setState(() {
          _bundles = parsed;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addBundleToCart(JsonMap bundle) async {
    final int bundleId = int.tryParse(bundle['id']?.toString() ?? '0') ?? 0;
    if (bundleId <= 0 || _addingBundleId != null) return;

    HapticFeedback.lightImpact();
    setState(() => _addingBundleId = bundleId);
    try {
      final response = await ApiService.httpClient
          .post(
            Uri.parse('$_domain/api/v1/bundles/$bundleId/add'),
            headers: ApiService.buildHeaders(widget.token, isJson: true),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        HapticFeedback.mediumImpact();
        ref.read(cartCountProvider.notifier).fetchCartCount(widget.token);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ?? 'Bundle items added to your cart!',
            ),
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
              data is Map
                  ? (data['message']?.toString() ?? 'Unable to add bundle.')
                  : 'Unable to add bundle.',
            ),
            backgroundColor: StorkTheme.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error occurred.'),
            backgroundColor: StorkTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _addingBundleId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Bundle Deals & Free Gifts'),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchBundles(),
              child: _bundles.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(28),
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
                              Icons.redeem_rounded,
                              size: 38,
                              color: StorkTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Active Bundle Deals Right Now',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Seller multi-item bundles and Buy X Get Y free gift promotions will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: StorkTheme.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _bundles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        return _buildBundleCard(_bundles[index]);
                      },
                    ),
            ),
    );
  }

  Widget _buildBundleCard(JsonMap bundle) {
    final int bundleId = int.tryParse(bundle['id']?.toString() ?? '0') ?? 0;
    final String title = bundle['title']?.toString() ?? 'Store Bundle Deal';
    final String bundleType =
        bundle['bundle_type']?.toString() ?? 'percentage_off';
    final int reqQty =
        int.tryParse(bundle['required_quantity']?.toString() ?? '2') ?? 2;
    final double discPct =
        double.tryParse(bundle['discount_percentage']?.toString() ?? '0') ??
            0.0;
    final sellerMap = bundle['seller_profile'] is Map
        ? JsonMap.from(bundle['seller_profile'] as Map)
        : (bundle['seller'] is Map
            ? JsonMap.from(bundle['seller'] as Map)
            : <String, dynamic>{});
    final String storeName =
        sellerMap['business_name']?.toString() ?? 'Verified Store';

    final dynamic rawProductsCandidate =
        bundle['products'] ?? bundle['qualifying_products'] ?? bundle['items'];
    final List<JsonMap> rawProducts = _extractBundlesList(rawProductsCandidate);
    final List<Product> products = [
      for (final p in rawProducts) Product.fromJson(p),
    ];

    final JsonMap? freeGiftMap = bundle['free_gift_product'] is Map
        ? JsonMap.from(bundle['free_gift_product'] as Map)
        : (bundle['free_gift'] is Map
            ? JsonMap.from(bundle['free_gift'] as Map)
            : null);
    final String giftVar = [
      bundle['free_gift_variant_name'],
      bundle['free_gift_sub_variant_name']
    ]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .join(' / ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(22),
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: bundleType == 'percentage_off'
                      ? StorkTheme.brandGradient
                      : const LinearGradient(
                          colors: [Color(0xFF6D28D9), Color(0xFF9333EA)],
                        ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  bundleType == 'percentage_off'
                      ? 'BUY $reqQty GET ${discPct.toStringAsFixed(0)}% OFF'
                      : 'BUY $reqQty GET FREE GIFT (\u20B10.00)',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    size: 14,
                    color: StorkTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: StorkTheme.primaryDark,
            ),
          ),
          if (freeGiftMap != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.card_giftcard_rounded,
                    color: Color(0xFF7C3AED),
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Free Gift: ${freeGiftMap['name'] ?? 'Bonus Item'}${giftVar.isNotEmpty ? ' ($giftVar)' : ''} \u2014 \u20B10.00',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6D28D9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (products.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 114,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, pIdx) {
                  final prod = products[pIdx];
                  final imgUrl = prod.pictures.isNotEmpty
                      ? ApiConfig.storageUrl(prod.pictures.first, _domain)
                      : '';

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        StorkRoute.fade(
                          ProductShowScreen(
                            product: prod,
                            baseUrl: _domain,
                            token: widget.token,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 204,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: StorkTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: StorkTheme.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 58,
                              height: 58,
                              color: StorkTheme.surface,
                              child: imgUrl.isNotEmpty
                                  ? Image.network(imgUrl, fit: BoxFit.cover)
                                  : const Icon(
                                      Icons.inventory_2_outlined,
                                      color: StorkTheme.textMuted,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    prod.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: StorkTheme.textMain,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '\u20B1${_formatMoney(prod.discountedPrice)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                    color: StorkTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _addingBundleId != null
                  ? null
                  : () => _addBundleToCart(bundle),
              icon: _addingBundleId == bundleId
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: Text(
                _addingBundleId == bundleId
                    ? 'Adding Bundle...'
                    : 'Add Bundle to Cart (Min $reqQty Items)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
