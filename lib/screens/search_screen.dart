import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/product_card.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../models/seller_profile_model.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'seller_store_screen.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef StringMap = Map<String, String>;

class SearchScreen extends StatefulWidget {
  final String baseUrl;
  final String token;
  final String initialQuery;

  const SearchScreen({
    super.key,
    required this.baseUrl,
    required this.token,
    this.initialQuery = '',
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late TextEditingController _searchController;
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;
  Timer? _wsDebounceTimer;
  int _searchRequestSeq = 0;

  bool _isInitialLoading = true;
  bool _isSyncing = false;
  bool _isFetchingMore = false;

  List<Product> _products = [];
  List<SellerProfile> _matchedSellers = [];
  List<String> _suggestions = [];

  String _selectedCategory = 'All';
  String _sortBy = 'relevance';
  int _currentPage = 1;
  bool _hasMore = false;

  static const List<String> _categories = [
    'All',
    'Pet',
    'Kids',
    'Electronics',
    'Home & Garden',
    'Women\'s',
    'Men\'s',
    'Health & Beauty',
    'Books & Media',
    'Sports & Outdoors',
    'Food & Gourmet',
    'Furniture & Office',
    'Jewelry & Watches',
  ];

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _scrollController.addListener(_onScroll);
    _performSearch(resetPage: true, initialLoad: true);
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'catalog' || event.scope == 'marketplace') {
      _wsDebounceTimer?.cancel();
      _wsDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && !_isSyncing && !_isFetchingMore) {
          _performSearch(resetPage: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _wsDebounceTimer?.cancel();
    WebSocketService.removeListener(_onRealtimeEvent);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 220) {
      if (!_isFetchingMore && _hasMore && !_isSyncing) {
        _performSearch(loadMore: true);
      }
    }
  }

  void _onQueryChanged(String value) {
    setState(() {});
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestionsSilently(value.trim());
      _performSearch(resetPage: true);
    });
  }

  Future<void> _fetchSuggestionsSilently(String query) async {
    if (query.length < 2) {
      if (mounted && _suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }
    try {
      final uri = Uri.parse('$_domain/api/v1/search/suggestions').replace(
        queryParameters: {'q': query},
      );
      final response = await ApiService.httpClient
          .get(
            uri,
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(const Duration(seconds: 6));

      if (!mounted || response.statusCode != 200) return;
      final body = json.decode(response.body);
      final dynamic raw = body is Map ? (body['data'] ?? body) : body;
      List<dynamic> list = [];
      if (raw is List) {
        list = raw;
      } else if (raw is Map && raw['suggestions'] is List) {
        list = raw['suggestions'] as List<dynamic>;
      }
      setState(() {
        _suggestions = [
          for (final item in list)
            if (item is Map && item['name'] != null)
              item['name'].toString()
            else if (item != null && item is! Map)
              item.toString(),
        ].take(6).toList();
      });
    } catch (_) {}
  }

  JsonList _extractMapList(dynamic raw, List<String> keys) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) JsonMap.from(item),
      ];
    }
    if (raw is Map) {
      for (final key in keys) {
        if (raw.containsKey(key) && raw[key] != null && raw[key] != raw) {
          final extracted = _extractMapList(raw[key], keys);
          if (extracted.isNotEmpty) return extracted;
        }
      }
    }
    return [];
  }

  Future<void> _performSearch({
    bool resetPage = false,
    bool loadMore = false,
    bool initialLoad = false,
  }) async {
    final int reqId = ++_searchRequestSeq;

    if (loadMore) {
      setState(() => _isFetchingMore = true);
    } else {
      if (resetPage) _currentPage = 1;
      setState(() {
        if (initialLoad && _products.isEmpty) {
          _isInitialLoading = true;
        } else {
          _isSyncing = true;
        }
      });
    }

    final int targetPage = loadMore ? _currentPage + 1 : 1;
    final String q = _searchController.text.trim();

    try {
      final StringMap params = {
        'page': '$targetPage',
        if (q.isNotEmpty) 'q': q,
        if (q.isNotEmpty) 'search': q,
        if (_selectedCategory != 'All') 'category': _selectedCategory,
        if (_sortBy != 'relevance') 'sort': _sortBy,
      };

      final uri =
          Uri.parse('$_domain/api/v1/search').replace(queryParameters: params);
      final response = await ApiService.httpClient
          .get(
            uri,
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted || reqId != _searchRequestSeq) return;

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final dynamic data = body is Map ? (body['data'] ?? body) : body;

        final JsonList rawProducts = _extractMapList(
          data,
          ['products', 'items', 'results', 'data'],
        );
        JsonList rawSellers = [];
        if (data is Map) {
          rawSellers = _extractMapList(
            data['sellers'] ?? data['stores'] ?? data['matched_sellers'],
            ['sellers', 'stores', 'data'],
          );
        }

        int current = targetPage;
        int last = targetPage;
        if (data is Map) {
          final prodBlock = data['products'] ?? data;
          if (prodBlock is Map) {
            current = int.tryParse(
                    prodBlock['current_page']?.toString() ?? '$targetPage') ??
                targetPage;
            last = int.tryParse(
                    prodBlock['last_page']?.toString() ?? '$targetPage') ??
                targetPage;
          }
        }

        final List<Product> parsedProducts = [
          for (final p in rawProducts) Product.fromJson(p),
        ];
        final List<SellerProfile> parsedSellers = [
          for (final s in rawSellers) SellerProfile.fromJson(s),
        ];

        setState(() {
          if (loadMore) {
            final existingIds = _products.map((p) => p.id).toSet();
            for (final item in parsedProducts) {
              if (!existingIds.contains(item.id)) {
                _products.add(item);
              }
            }
          } else {
            _products = parsedProducts;
            _matchedSellers = parsedSellers;
          }
          _applyClientSort();
          _currentPage = current;
          _hasMore = current < last;
          _isInitialLoading = false;
          _isSyncing = false;
          _isFetchingMore = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted && reqId == _searchRequestSeq) {
      setState(() {
        _isInitialLoading = false;
        _isSyncing = false;
        _isFetchingMore = false;
      });
    }
  }

  void _applyClientSort() {
    switch (_sortBy) {
      case 'price_asc':
        _products
            .sort((a, b) => a.discountedPrice.compareTo(b.discountedPrice));
        break;
      case 'price_desc':
        _products
            .sort((a, b) => b.discountedPrice.compareTo(a.discountedPrice));
        break;
      case 'top_sales':
        _products.sort((a, b) => b.soldCount.compareTo(a.soldCount));
        break;
      case 'newest':
        _products.sort((a, b) => b.id.compareTo(a.id));
        break;
      case 'relevance':
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 700 ? 3 : 2;
    final aspectRatio = width < 340 ? 0.56 : (width < 380 ? 0.61 : 0.66);

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _searchController,
            autofocus: widget.initialQuery.isEmpty,
            onChanged: _onQueryChanged,
            onSubmitted: (_) {
              setState(() => _suggestions = []);
              _performSearch(resetPage: true);
            },
            decoration: InputDecoration(
              hintText: 'Search products, brands, or stores...',
              fillColor: StorkTheme.surfaceSubtle,
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 19,
                color: StorkTheme.primary,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _suggestions = []);
                        _performSearch(resetPage: true);
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Column(
            children: [
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final active = _selectedCategory == cat;
                    return GestureDetector(
                      onTap: () {
                        if (_selectedCategory == cat) return;
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategory = cat);
                        _performSearch(resetPage: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: active ? StorkTheme.brandGradient : null,
                          color: active ? null : StorkTheme.surfaceSubtle,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: active
                                ? StorkTheme.primary
                                : StorkTheme.borderSubtle,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: active ? Colors.white : StorkTheme.textMain,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: const BoxDecoration(
                  color: StorkTheme.surface,
                  border: Border(
                    top: BorderSide(color: StorkTheme.borderSubtle),
                    bottom: BorderSide(color: StorkTheme.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    _buildSortTab('relevance', 'Relevance'),
                    _buildSortTab('top_sales', 'Top Sales'),
                    _buildSortTab('newest', 'Newest'),
                    _buildSortTab(
                      _sortBy == 'price_asc' ? 'price_desc' : 'price_asc',
                      _sortBy == 'price_asc'
                          ? 'Price \u2191'
                          : (_sortBy == 'price_desc'
                              ? 'Price \u2193'
                              : 'Price'),
                      isPriceToggle: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isInitialLoading && _products.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                if (_suggestions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: StorkTheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: StorkTheme.borderSubtle),
                        boxShadow: StorkTheme.softCardShadow,
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final sug in _suggestions)
                            ActionChip(
                              backgroundColor: StorkTheme.surfaceSubtle,
                              side: const BorderSide(
                                  color: StorkTheme.borderSubtle),
                              label: Text(
                                sug,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                _searchController.text = sug;
                                setState(() => _suggestions = []);
                                _performSearch(resetPage: true);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                if (_matchedSellers.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Text(
                            'MATCHING OFFICIAL STORES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: StorkTheme.primaryDark,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 84,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            itemCount: _matchedSellers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final seller = _matchedSellers[index];
                              final logoUrl = seller.logoPath != null
                                  ? ApiConfig.storageUrl(
                                      seller.logoPath, _domain)
                                  : '';
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    StorkRoute.fade(
                                      SellerStoreScreen(
                                        sellerProfile: seller,
                                        baseUrl: _domain,
                                        token: widget.token,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 215,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: StorkTheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: StorkTheme.borderSubtle),
                                    boxShadow: StorkTheme.softCardShadow,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 21,
                                        backgroundColor: StorkTheme.primary
                                            .withValues(alpha: 0.12),
                                        backgroundImage: logoUrl.isNotEmpty
                                            ? NetworkImage(logoUrl)
                                            : null,
                                        child: logoUrl.isEmpty
                                            ? Text(
                                                seller.businessName.isNotEmpty
                                                    ? seller.businessName[0]
                                                        .toUpperCase()
                                                    : 'S',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: StorkTheme.primary,
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              seller.businessName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w800,
                                                color: StorkTheme.primaryDark,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              seller.lineOfBusiness,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: StorkTheme.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: StorkTheme.textMuted,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                _products.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: StorkTheme.primary
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.search_off_rounded,
                                    size: 34,
                                    color: StorkTheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'No Matching Products Found',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: StorkTheme.primaryDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Try adjusting your search keywords or switching category filters.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: StorkTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: aspectRatio,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return ProductCard(
                                product: _products[index],
                                baseUrl: _domain,
                                token: widget.token,
                              );
                            },
                            childCount: _products.length,
                          ),
                        ),
                      ),
                if (_isFetchingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: StorkTheme.primary,
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
    );
  }

  Widget _buildSortTab(
    String key,
    String label, {
    bool isPriceToggle = false,
  }) {
    final bool active = isPriceToggle
        ? (_sortBy == 'price_asc' || _sortBy == 'price_desc')
        : _sortBy == key;

    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _sortBy = key;
            _applyClientSort();
          });
          _performSearch(resetPage: true);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? StorkTheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                color: active ? StorkTheme.primary : StorkTheme.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
