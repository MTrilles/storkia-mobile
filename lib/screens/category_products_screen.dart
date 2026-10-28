import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/product_model.dart';
import '../components/product_card.dart';

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
  List<Product> _products = [];
  int _currentPage = 1;
  bool _hasMore = true;

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
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isFetchingMore && _hasMore) {
        _fetchCategoryData(loadMore: true);
      }
    }
  }

  Future<void> _fetchCategoryData({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMore || _isFetchingMore) return;
      setState(() => _isFetchingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        if (!loadMore) _currentPage = 1;
      });
    }

    try {
      final page = loadMore ? _currentPage + 1 : 1;

      // Fix 1: Dynamically build the URL to prevent sending "subcategory=All" to the backend
      String urlString =
          '${widget.baseUrl}/api/v1/category/${widget.slug}?page=$page';
      if (_selectedSubcategory != 'All') {
        urlString +=
            '&subcategory=${Uri.encodeComponent(_selectedSubcategory)}';
      }

      final uri = Uri.parse(urlString);

      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization':
            'Bearer ${widget.token}', // Fix 2: Uncommented Auth header
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final payload = data['data'];
          final paginatedData = payload['products'];
          final List newProductsJson = paginatedData['data'];

          setState(() {
            _categoryName = payload['category_name'];
            if (!loadMore) {
              _subcategories = [
                'All',
                ...(payload['subcategories'] as List).map((e) => e.toString())
              ];
              _products = newProductsJson
                  .map((json) => Product.fromJson(json))
                  .toList();
            } else {
              _products.addAll(newProductsJson
                  .map((json) => Product.fromJson(json))
                  .toList());
            }

            _currentPage = paginatedData['current_page'];
            _hasMore = _currentPage < paginatedData['last_page'];
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load category.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error.')),
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

  void _onSubcategorySelected(String subcategory) {
    if (_selectedSubcategory == subcategory) return;

    setState(() {
      _selectedSubcategory = subcategory;
      _products.clear();
      _hasMore = true;
      _currentPage = 1;
    });

    _fetchCategoryData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF292524)),
        title: Text(
          _categoryName.isEmpty ? 'Loading...' : _categoryName,
          style: const TextStyle(
            color: Color(0xFF292524),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_subcategories.isNotEmpty)
            Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.black.withOpacity(0.05)),
                ),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _subcategories.length,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemBuilder: (context, index) {
                  final filter = _subcategories[index];
                  final isSelected = _selectedSubcategory == filter;

                  return GestureDetector(
                    onTap: () => _onSubcategorySelected(filter),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFCF4173)
                            : const Color(0xFFF5F5F4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFCF4173)
                              : const Color(0xFFE7E5E4),
                        ),
                      ),
                      child: Text(
                        filter,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF78716C),
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: _isLoading && !_isFetchingMore
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFCF4173)))
                : CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      _products.isEmpty
                          ? const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Center(
                                    child: Text(
                                        'No products found in this category.')),
                              ),
                            )
                          : SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.7,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    return ProductCard(
                                      product: _products[index],
                                      baseUrl: widget.baseUrl,
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
                                  color: Color(0xFFCF4173)),
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
