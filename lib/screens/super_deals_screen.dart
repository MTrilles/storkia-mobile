import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import 'product_show.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;

class SuperDealsScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const SuperDealsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<SuperDealsScreen> createState() => _SuperDealsScreenState();
}

class _SuperDealsScreenState extends State<SuperDealsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  JsonList _deals = [];
  String _selectedFilter = 'all';
  Timer? _autoSyncTimer;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchDeals();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _fetchDeals(silent: true);
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
      _fetchDeals(silent: true);
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

  JsonList _extractDealsList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) JsonMap.from(item),
      ];
    }
    if (raw is Map) {
      final JsonList combined = [];
      for (final key in [
        'super_deals',
        'deals',
        'store_sales',
        'items',
        'products',
        'data',
      ]) {
        if (raw.containsKey(key) && raw[key] != null && raw[key] != raw) {
          final extracted = _extractDealsList(raw[key]);
          if (extracted.isNotEmpty) {
            combined.addAll(extracted);
          }
        }
      }
      if (combined.isNotEmpty) return combined;
    }
    return [];
  }

  Future<void> _fetchDeals({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      };

      final response = await http
          .get(Uri.parse('$_domain/api/v1/super-deals'), headers: headers)
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      JsonList parsed = [];
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        parsed = _extractDealsList(body is Map ? (body['data'] ?? body) : body);
      }

      if (parsed.isEmpty) {
        final homeRes = await http
            .get(Uri.parse('$_domain/api/v1/home'), headers: headers)
            .timeout(ApiConfig.requestTimeout);
        if (!mounted) return;
        if (homeRes.statusCode == 200) {
          final homeBody = json.decode(homeRes.body);
          if (homeBody is Map && homeBody['data'] is Map) {
            final homeData = JsonMap.from(homeBody['data'] as Map);
            parsed = _extractDealsList(homeData['super_deals']);
          }
        }
      }

      if (mounted) {
        setState(() {
          _deals = parsed;
          _isLoading = false;
        });
      }
      return;
    } catch (_) {}
    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  JsonList get _filteredDeals {
    if (_selectedFilter == 'all') return _deals;
    return _deals.where((d) {
      final type = (d['deal_type'] ?? 'super_deal').toString().toLowerCase();
      return type == _selectedFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredDeals;
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 700 ? 3 : 2;
    final aspectRatio = width < 350 ? 0.59 : 0.64;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Super Deals & Flash Sales'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: StorkTheme.brandGradient,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '⚡ LIMITED-SLOT SUPER DEALS',
                    style: TextStyle(
                      color: StorkTheme.brandLight,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Variant-Aware Flash Slots & Store Sales',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Super Deal slot prices automatically apply at checkout while slot stock lasts.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All Deals (${_deals.length})'),
                      const SizedBox(width: 8),
                      _buildFilterChip('super_deal', 'Super Deal Slots'),
                      const SizedBox(width: 8),
                      _buildFilterChip('store_sale', 'Store Sales'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: StorkTheme.primary),
                  )
                : RefreshIndicator(
                    color: StorkTheme.primary,
                    onRefresh: () => _fetchDeals(),
                    child: visible.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(28),
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Container(
                                  width: 74,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    color: StorkTheme.primary
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.bolt_rounded,
                                    size: 38,
                                    color: StorkTheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No Active Super Deals Right Now',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Check back soon for new time-slot flash promotions!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: StorkTheme.textMuted,
                                ),
                              ),
                            ],
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(14),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              childAspectRatio: aspectRatio,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              return _buildDealCard(visible[index]);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final active = _selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6.5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: active ? StorkTheme.primaryDark : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDealCard(JsonMap entry) {
    final prodMap =
        entry['product'] is Map ? JsonMap.from(entry['product'] as Map) : entry;
    final product = Product.fromJson(prodMap);

    final double dealPrice = double.tryParse((entry['deal_price'] ??
                entry['effective_price'] ??
                product.discountedPrice)
            .toString()) ??
        product.discountedPrice;
    final double origPrice = double.tryParse(
            (entry['original_price'] ?? entry['regular_price'] ?? product.price)
                .toString()) ??
        product.price;
    final double pct = double.tryParse(
            (entry['discount_percentage'] ?? product.effectiveDiscountPercent)
                .toString()) ??
        0;
    final int flashQty =
        int.tryParse(entry['flash_quantity']?.toString() ?? '0') ?? 0;
    final int soldQty =
        int.tryParse(entry['sold_quantity']?.toString() ?? '0') ?? 0;
    final double ratio =
        flashQty > 0 ? (soldQty / flashQty).clamp(0.0, 1.0) : 0.3;

    final String variantScope = [
      entry['variant_name'],
      entry['sub_variant_name']
    ]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .join(' / ');

    final String imgUrl = product.pictures.isNotEmpty
        ? ApiConfig.storageUrl(product.pictures.first, _domain)
        : '';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          StorkRoute.fade(
            ProductShowScreen(
              product: product,
              baseUrl: _domain,
              token: widget.token,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: StorkTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: StorkTheme.primary.withValues(alpha: 0.35),
          ),
          boxShadow: StorkTheme.softCardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: StorkTheme.surfaceSubtle,
                    child: imgUrl.isNotEmpty
                        ? Image.network(imgUrl, fit: BoxFit.cover)
                        : const Icon(
                            Icons.inventory_2_outlined,
                            color: StorkTheme.textMuted,
                          ),
                  ),
                  if (pct > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [StorkTheme.danger, StorkTheme.primary],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⚡ -${pct.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                    ),
                  ),
                  if (variantScope.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Option: $variantScope',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '₱${_formatMoney(dealPrice)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: StorkTheme.price,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '₱${_formatMoney(origPrice)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            decoration: TextDecoration.lineThrough,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 9,
                      backgroundColor:
                          StorkTheme.primary.withValues(alpha: 0.14),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        StorkTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    flashQty > 0
                        ? '$soldQty / $flashQty Sold'
                        : 'Store Sale Active',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
