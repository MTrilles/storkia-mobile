import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/product_model.dart';
import '../components/custom_bottom_nav.dart';
import '../components/product_card.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  final String token;

  const HomeScreen({super.key, required this.user, required this.token});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final ScrollController _scrollController = ScrollController();

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
      setState(() => _isLoading = true);
    }

    final result =
        await ApiService.getProducts(widget.token, page: _currentPage);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      body: SafeArea(
        child: Column(
          children: [
            // Custom Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/icon.webp',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE7E5E4)),
                      ),
                      child: const TextField(
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search products...',
                          hintStyle: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF78716C),
                              height: 1.2),
                          prefixIcon: Icon(Icons.search,
                              size: 20, color: Color(0xFF78716C)),
                          prefixIconConstraints:
                              BoxConstraints(minWidth: 40, minHeight: 40),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(right: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.shopping_cart_outlined,
                      color: Color(0xFF292524)),
                  const SizedBox(width: 16),
                  const Icon(Icons.chat_bubble_outline,
                      color: Color(0xFF292524)),
                ],
              ),
            ),

            // Scrollable Content using CustomScrollView for better performance
            Expanded(
              child: _isLoading && !_isFetchingMore
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFCF4173)))
                  : CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Hero Banner
                              Container(
                                width: double.infinity,
                                height: 160,
                                margin: const EdgeInsets.only(bottom: 16.0),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF6D8BD),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: 24,
                                      top: 40,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFCF4173),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'FLASH SALE',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Special Offer',
                                            style: TextStyle(
                                              color: Color(0xFF5D3140),
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Up to 50% Off on selected items',
                                            style: TextStyle(
                                              color: Color(0xFFCF4173),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Text(
                                  'Discover Products',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF292524),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Products Grid
                        _products.isEmpty
                            ? const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Center(
                                      child: Text('No products available.')),
                                ),
                              )
                            : SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
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

                        // Loading Indicator at bottom
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
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
