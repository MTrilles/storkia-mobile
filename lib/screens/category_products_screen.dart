import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../components/product_card.dart';
import '../services/api_service.dart';

class CategoryProductsScreen extends StatefulWidget {
  final String categoryName;
  final List<String> subcategories;
  final String token;

  const CategoryProductsScreen({
    super.key,
    required this.categoryName,
    required this.subcategories,
    required this.token,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final ScrollController _scrollController = ScrollController();

  String _selectedSubcategory = 'All';
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
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
        _fetchProducts(loadMore: true);
      }
    }
  }

  Future<void> _fetchProducts({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _isFetchingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        if (!loadMore) _currentPage = 1;
      });
    }

    final result = await ApiService.getProducts(
      widget.token,
      page: _currentPage,
      category: widget.categoryName,
      subcategory: _selectedSubcategory == 'All' ? null : _selectedSubcategory,
    );

    if (result['success']) {
      final Map<String, dynamic> paginatedData =
          result['data']['data'] ?? result['data'];
      final List<dynamic> productsJson = paginatedData['data'] ?? [];
      final int lastPage = paginatedData['last_page'] ?? 1;

      final List<Product> newProducts =
          productsJson.map((json) => Product.fromJson(json)).toList();

      setState(() {
        if (loadMore) {
          _products.addAll(newProducts);
        } else {
          _products = newProducts;
        }

        if (_currentPage >= lastPage) {
          _hasMore = false;
        } else {
          _currentPage++;
        }

        _isLoading = false;
        _isFetchingMore = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _isFetchingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'])),
        );
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
    _fetchProducts();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ['All', ...widget.subcategories];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF292524)),
        title: Text(
          widget.categoryName,
          style: const TextStyle(
            color: Color(0xFF292524),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          // Subcategory Filter List
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
              itemCount: filters.length,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemBuilder: (context, index) {
                final isSelected = _selectedSubcategory == filters[index];
                return GestureDetector(
                  onTap: () => _onSubcategorySelected(filters[index]),
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
                      filters[index],
                      style: TextStyle(
                        color:
                            isSelected ? Colors.white : const Color(0xFF78716C),
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

          // Products Grid
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
                                      baseUrl: 'https://dev.storkia.shop',
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
