import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../providers/wishlist_provider.dart';
import 'product_show.dart';

typedef JsonMap = Map<String, dynamic>;

class TrendsScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;

  const TrendsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  List<JsonMap> _trendEntries = [];
  final Map<int, bool> _wishlistOverrides = {};
  String _selectedCategory = 'All';
  String _sortBy = 'trending';
  Timer? _autoSyncTimer;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchTrends();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _fetchTrends(silent: true);
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
      _fetchTrends(silent: true);
    }
  }

  List<JsonMap> _extractMapList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    if (raw is Map) {
      for (final key in [
        'trends',
        'trending',
        'items',
        'products',
        'entries',
        'results',
        'data',
      ]) {
        if (raw.containsKey(key) && raw[key] != null && raw[key] != raw) {
          final extracted = _extractMapList(raw[key]);
          if (extracted.isNotEmpty) return extracted;
        }
      }
      for (final value in raw.values) {
        if (value is List) {
          final extracted = _extractMapList(value);
          if (extracted.isNotEmpty) return extracted;
        }
      }
    }
    return [];
  }

  Future<void> _fetchTrends({bool silent = false}) async {
    if (!silent && _trendEntries.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final headers = {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      };

      final response = await http
          .get(Uri.parse('$_domain/api/v1/trends'), headers: headers)
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      List<JsonMap> parsed = [];
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        parsed = _extractMapList(body is Map ? (body['data'] ?? body) : body);
      }

      if (parsed.isEmpty) {
        final homeRes = await http
            .get(Uri.parse('$_domain/api/v1/home'), headers: headers)
            .timeout(ApiConfig.requestTimeout);
        if (!mounted) return;
        if (homeRes.statusCode == 200) {
          final homeBody = json.decode(homeRes.body);
          if (homeBody is Map && homeBody['data'] is Map) {
            final homeData = Map<String, dynamic>.from(homeBody['data'] as Map);
            parsed = _extractMapList(homeData['trending']);
          }
        }
      }

      if (mounted) {
        setState(() {
          _trendEntries = parsed;
          _isLoading = false;
        });
      }
      return;
    } catch (_) {}

    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Product _productFromEntry(JsonMap entry) {
    final JsonMap prodMap = entry['product'] is Map
        ? Map<String, dynamic>.from(entry['product'] as Map)
        : entry;
    return Product.fromJson(prodMap);
  }

  String _categoryOfEntry(JsonMap entry) {
    final prod = _productFromEntry(entry);
    final cat = (prod.category ??
            entry['category']?.toString() ??
            prod.sellerProfile?.lineOfBusiness ??
            '')
        .trim();
    return cat;
  }

  int _ordersThisMonthOfEntry(JsonMap entry, Product product) {
    for (final key in [
      'orders_this_month',
      'monthly_orders',
      'recent_orders_count',
      'orders_count',
      'sold_count',
      'total_sold_units',
    ]) {
      final val = int.tryParse(entry[key]?.toString() ?? '');
      if (val != null && val > 0) return val;
    }
    return product.soldCount;
  }

  String _metricCaptionOfEntry(JsonMap entry, Product product) {
    for (final key in [
      'metric_label',
      'reason',
      'label',
      'caption',
      'badge_text',
      'trend_label',
    ]) {
      final val = entry[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    final count = _ordersThisMonthOfEntry(entry, product);
    if (count > 0) {
      return '$count ordered this month';
    }
    if (product.effectiveDiscountPercent > 0) {
      return 'Save ${product.effectiveDiscountPercent.toStringAsFixed(0)}%';
    }
    return 'New & trending';
  }

  Map<String, int> get _categoryCounts {
    final Map<String, int> counts = {'All': _trendEntries.length};
    for (final entry in _trendEntries) {
      final cat = _categoryOfEntry(entry);
      if (cat.isNotEmpty) {
        counts[cat] = (counts[cat] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<JsonMap> get _filteredAndSortedEntries {
    final filtered = _trendEntries.where((entry) {
      if (_selectedCategory == 'All') return true;
      return _categoryOfEntry(entry).toLowerCase() ==
          _selectedCategory.toLowerCase();
    }).toList();

    switch (_sortBy) {
      case 'most_ordered':
        filtered.sort((a, b) {
          final pA = _productFromEntry(a);
          final pB = _productFromEntry(b);
          return _ordersThisMonthOfEntry(b, pB)
              .compareTo(_ordersThisMonthOfEntry(a, pA));
        });
        break;
      case 'price_asc':
        filtered.sort((a, b) => _productFromEntry(a)
            .discountedPrice
            .compareTo(_productFromEntry(b).discountedPrice));
        break;
      case 'price_desc':
        filtered.sort((a, b) => _productFromEntry(b)
            .discountedPrice
            .compareTo(_productFromEntry(a).discountedPrice));
        break;
      case 'newest':
        filtered.sort((a, b) =>
            _productFromEntry(b).id.compareTo(_productFromEntry(a).id));
        break;
      case 'trending':
      default:
        break;
    }

    return filtered;
  }

  String _formatMoney(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 700 ? 3 : 2;
    final categoryCounts = _categoryCounts;
    final visibleEntries = _filteredAndSortedEntries;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Trending & Best Sellers'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchTrends(),
              child: _trendEntries.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 110),
                        Center(
                          child: Text(
                            'No trending products recorded yet.',
                            style: TextStyle(color: StorkTheme.textMuted),
                          ),
                        ),
                      ],
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                margin:
                                    const EdgeInsets.fromLTRB(14, 14, 14, 10),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: StorkTheme.brandLight
                                      .withValues(alpha: 0.38),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: StorkTheme.borderSubtle,
                                  ),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.trending_up_rounded,
                                          color: StorkTheme.primary,
                                          size: 24,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Trends',
                                          style: TextStyle(
                                            color: StorkTheme.primaryDark,
                                            fontSize: 21,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'What shoppers on Storkia are searching for, ordering and saving the most over the last 30 days, with new arrivals mixed in.',
                                      style: TextStyle(
                                        color: StorkTheme.textMuted,
                                        fontSize: 12.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 36,
                                        child: ListView(
                                          scrollDirection: Axis.horizontal,
                                          children: categoryCounts.entries
                                              .map((entry) {
                                            final bool active =
                                                _selectedCategory == entry.key;
                                            return GestureDetector(
                                              onTap: () => setState(() =>
                                                  _selectedCategory =
                                                      entry.key),
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                    right: 8),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 13),
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: active
                                                      ? StorkTheme.primaryDark
                                                      : StorkTheme.surface,
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  border: Border.all(
                                                    color: active
                                                        ? StorkTheme.primaryDark
                                                        : StorkTheme
                                                            .borderSubtle,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      entry.key,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: active
                                                            ? Colors.white
                                                            : StorkTheme
                                                                .textMain,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      '${entry.value}',
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: active
                                                            ? StorkTheme
                                                                .brandLight
                                                            : StorkTheme
                                                                .textMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    PopupMenuButton<String>(
                                      initialValue: _sortBy,
                                      onSelected: (val) =>
                                          setState(() => _sortBy = val),
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'trending',
                                          child: Text('Most trending'),
                                        ),
                                        PopupMenuItem(
                                          value: 'most_ordered',
                                          child: Text('Most ordered'),
                                        ),
                                        PopupMenuItem(
                                          value: 'newest',
                                          child: Text('Newest arrivals'),
                                        ),
                                        PopupMenuItem(
                                          value: 'price_asc',
                                          child: Text('Price: Low to High'),
                                        ),
                                        PopupMenuItem(
                                          value: 'price_desc',
                                          child: Text('Price: High to Low'),
                                        ),
                                      ],
                                      child: Container(
                                        height: 36,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: StorkTheme.surface,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: StorkTheme.borderSubtle),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.sort_rounded,
                                              size: 16,
                                              color: StorkTheme.textMain,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Sort',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: StorkTheme.textMain,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              childAspectRatio: 0.65,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = visibleEntries[index];
                                final product = _productFromEntry(item);
                                final int rank = int.tryParse(
                                        item['rank']?.toString() ?? '') ??
                                    (index + 1);
                                final String metricCaption =
                                    _metricCaptionOfEntry(item, product);
                                final String imgUrl =
                                    product.pictures.isNotEmpty
                                        ? ApiConfig.storageUrl(
                                            product.pictures.first, _domain)
                                        : '';
                                final bool isWishlisted =
                                    _wishlistOverrides[product.id] ??
                                        product.isWishlisted;

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
                                          color: StorkTheme.borderSubtle),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Container(
                                                margin: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color:
                                                      StorkTheme.surfaceSubtle,
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child: imgUrl.isNotEmpty
                                                    ? Image.network(
                                                        imgUrl,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (_, __, ___) =>
                                                                const Icon(
                                                          Icons
                                                              .inventory_2_outlined,
                                                          color: StorkTheme
                                                              .textMuted,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons
                                                            .inventory_2_outlined,
                                                        color: StorkTheme
                                                            .textMuted,
                                                      ),
                                              ),
                                              Positioned(
                                                top: 14,
                                                right: 14,
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _wishlistOverrides[product
                                                          .id] = !isWishlisted;
                                                    });
                                                    ref
                                                        .read(wishlistProvider
                                                            .notifier)
                                                        .toggleWishlist(
                                                          _domain,
                                                          widget.token,
                                                          product,
                                                        );
                                                  },
                                                  child: Container(
                                                    width: 30,
                                                    height: 30,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.92),
                                                      shape: BoxShape.circle,
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                  alpha: 0.08),
                                                          blurRadius: 4,
                                                        ),
                                                      ],
                                                    ),
                                                    child: Icon(
                                                      isWishlisted
                                                          ? Icons
                                                              .favorite_rounded
                                                          : Icons
                                                              .favorite_border_rounded,
                                                      size: 16,
                                                      color: isWishlisted
                                                          ? StorkTheme.danger
                                                          : StorkTheme
                                                              .textMuted,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              11, 2, 11, 11),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                product.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: StorkTheme.textMain,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      '₱${_formatMoney(product.discountedPrice)}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 14.5,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color:
                                                            StorkTheme.textMain,
                                                      ),
                                                    ),
                                                  ),
                                                  if (product
                                                          .effectiveDiscountPercent >
                                                      0) ...[
                                                    const SizedBox(width: 5),
                                                    Flexible(
                                                      child: Text(
                                                        '₱${_formatMoney(product.price)}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 10.5,
                                                          decoration:
                                                              TextDecoration
                                                                  .lineThrough,
                                                          color: StorkTheme
                                                              .textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6.5,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: rank <= 3
                                                          ? StorkTheme
                                                              .primaryDark
                                                          : StorkTheme
                                                              .surfaceSubtle,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      border: rank <= 3
                                                          ? null
                                                          : Border.all(
                                                              color: StorkTheme
                                                                  .borderSubtle,
                                                            ),
                                                    ),
                                                    child: Text(
                                                      '#$rank',
                                                      style: TextStyle(
                                                        color: rank <= 3
                                                            ? Colors.white
                                                            : StorkTheme
                                                                .textMain,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      metricCaption,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            StorkTheme.primary,
                                                      ),
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
                                );
                              },
                              childCount: visibleEntries.length,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
            ),
    );
  }
}
