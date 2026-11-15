import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../components/product_card.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';

class CategoryProductsScreen extends StatefulWidget {
  final String slug;
  final String baseUrl;
  final String token;

  const CategoryProductsScreen({
    super.key,
    required this.slug,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isFetchingMore = false;
  String _categoryName = '';
  List<String> _subcategories = [];
  String _selectedSubcategory = 'All';
  String _sortBy = 'newest';

  List<Product> _allCachedProducts = [];
  List<Product> _products = [];
  int _currentPage = 1;
  bool _hasMore = true;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    _fetchCategoryData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 220) {
      if (!_isFetchingMore && _hasMore && !_isLoading) {
        _fetchCategoryData(loadMore: true);
      }
    }
  }

  Future<void> _fetchCategoryData({
    bool loadMore = false,
    bool silent = false,
  }) async {
    if (loadMore) {
      if (!_hasMore || _isFetchingMore) return;
      setState(() => _isFetchingMore = true);
    } else {
      setState(() {
        if (!silent && _products.isEmpty) _isLoading = true;
        _currentPage = 1;
      });
    }

    try {
      final page = loadMore ? _currentPage + 1 : 1;
      String urlString = '$_domain/api/v1/category/${widget.slug}?page=$page';
      if (_selectedSubcategory != 'All') {
        urlString +=
            '&subcategory=${Uri.encodeComponent(_selectedSubcategory)}';
      }

      final response = await http.get(
        Uri.parse(urlString),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['data'] is Map) {
          final payload = Map<String, dynamic>.from(data['data'] as Map);
          final dynamic rawProductsBlock =
              payload['products'] ?? payload['data'];
          List<dynamic> newProductsJson = [];
          int current = page;
          int lastPage = page;

          if (rawProductsBlock is Map) {
            if (rawProductsBlock['data'] is List) {
              newProductsJson =
                  List<dynamic>.from(rawProductsBlock['data'] as List);
            }
            current = int.tryParse(
                    rawProductsBlock['current_page']?.toString() ?? '$page') ??
                page;
            lastPage = int.tryParse(
                    rawProductsBlock['last_page']?.toString() ?? '$page') ??
                page;
          } else if (rawProductsBlock is List) {
            newProductsJson = List<dynamic>.from(rawProductsBlock);
            current = 1;
            lastPage = 1;
          }

          final List<Product> parsedProducts = [
            for (final json in newProductsJson)
              if (json is Map)
                Product.fromJson(Map<String, dynamic>.from(json)),
          ];

          setState(() {
            _categoryName = payload['category_name']?.toString() ??
                payload['category']?.toString() ??
                _categoryName;

            if (!loadMore) {
              final List<dynamic> rawSubs = payload['subcategories'] is List
                  ? List<dynamic>.from(payload['subcategories'] as List)
                  : <dynamic>[];
              if (rawSubs.isNotEmpty || _subcategories.isEmpty) {
                _subcategories = [
                  'All',
                  ...rawSubs.map((e) {
                    if (e is Map && e['name'] != null) {
                      return e['name'].toString();
                    }
                    return e.toString();
                  }),
                ];
              }
              _products = parsedProducts;
              if (_selectedSubcategory == 'All') {
                _allCachedProducts = List<Product>.from(parsedProducts);
              } else {
                final existingIds = _allCachedProducts.map((p) => p.id).toSet();
                for (final p in parsedProducts) {
                  if (!existingIds.contains(p.id)) {
                    _allCachedProducts.add(p);
                  }
                }
              }
            } else {
              _products.addAll(parsedProducts);
              final existingIds = _allCachedProducts.map((p) => p.id).toSet();
              for (final p in parsedProducts) {
                if (!existingIds.contains(p.id)) {
                  _allCachedProducts.add(p);
                }
              }
            }
            _currentPage = current;
            _hasMore = _currentPage < lastPage;
            _applySorting();
          });
        }
      }
    } catch (_) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load category products.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  void _applySorting() {
    if (_sortBy == 'price_asc') {
      _products.sort((a, b) => a.discountedPrice.compareTo(b.discountedPrice));
    } else if (_sortBy == 'price_desc') {
      _products.sort((a, b) => b.discountedPrice.compareTo(a.discountedPrice));
    } else if (_sortBy == 'az') {
      _products
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      _products.sort((a, b) => b.id.compareTo(a.id));
    }
  }

  String get _sortLabel {
    switch (_sortBy) {
      case 'price_asc':
        return 'Price: Low to High';
      case 'price_desc':
        return 'Price: High to Low';
      case 'az':
        return 'Name: A to Z';
      default:
        return 'Newest First';
    }
  }

  void _onSubcategorySelected(String subcategory) {
    if (_selectedSubcategory == subcategory) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedSubcategory = subcategory;
      if (subcategory == 'All') {
        _products = List<Product>.from(_allCachedProducts);
      } else {
        _products = _allCachedProducts
            .where((p) =>
                (p.subcategory ?? '').toLowerCase() ==
                subcategory.toLowerCase())
            .toList();
      }
      _applySorting();
      _hasMore = true;
      _currentPage = 1;
    });
    _fetchCategoryData(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth >= 700 ? 3 : 2;
    final childAspectRatio =
        screenWidth < 340 ? 0.56 : (screenWidth < 380 ? 0.61 : 0.66);

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_categoryName.isEmpty ? 'Category' : _categoryName),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Sort Products',
            onSelected: (val) {
              HapticFeedback.selectionClick();
              setState(() {
                _sortBy = val;
                _applySorting();
              });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'newest', child: Text('Newest First')),
              PopupMenuItem(
                  value: 'price_asc', child: Text('Price: Low to High')),
              PopupMenuItem(
                  value: 'price_desc', child: Text('Price: High to Low')),
              PopupMenuItem(value: 'az', child: Text('Name: A to Z')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_subcategories.isNotEmpty)
            Container(
              height: 54,
              decoration: const BoxDecoration(
                color: StorkTheme.surface,
                border: Border(
                  bottom: BorderSide(color: StorkTheme.borderSubtle),
                ),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _subcategories.length,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _subcategories[index];
                  final isSelected = _selectedSubcategory == filter;
                  return GestureDetector(
                    onTap: () => _onSubcategorySelected(filter),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: isSelected ? StorkTheme.brandGradient : null,
                        color: isSelected ? null : StorkTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? StorkTheme.primary
                              : StorkTheme.borderSubtle,
                        ),
                      ),
                      child: Text(
                        filter,
                        style: TextStyle(
                          color:
                              isSelected ? Colors.white : StorkTheme.textMain,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: StorkTheme.surface,
              border: Border(
                bottom: BorderSide(color: StorkTheme.borderSubtle),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Showing ${_products.length} product(s) in $_selectedSubcategory',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: StorkTheme.textMuted,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.sort_rounded,
                      size: 14,
                      color: StorkTheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sortLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading && _products.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: StorkTheme.primary),
                  )
                : RefreshIndicator(
                    color: StorkTheme.primary,
                    onRefresh: () => _fetchCategoryData(silent: true),
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        const SliverToBoxAdapter(child: SizedBox(height: 14)),
                        _products.isEmpty
                            ? SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(40.0),
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
                                            Icons.inventory_2_outlined,
                                            size: 32,
                                            color: StorkTheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'No products found in this subcategory',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: StorkTheme.primaryDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    childAspectRatio: childAspectRatio,
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
                              padding: EdgeInsets.all(24.0),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: StorkTheme.primary,
                                ),
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
