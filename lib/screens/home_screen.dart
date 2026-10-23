import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/product_model.dart';
import '../components/custom_bottom_nav.dart';
import '../components/product_card.dart';
import '../services/api_service.dart';
import 'browse_screen.dart';
import 'me_screen.dart';
import 'cart_screen.dart';

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

  int _cartItemCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _fetchCartItemCount();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_currentIndex != 0) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isFetchingMore && _hasMore) {
        _fetchProducts(loadMore: true);
      }
    }
  }

  Future<void> _fetchCartItemCount() async {
    try {
      final response = await http.get(
        Uri.parse('https://dev.storkia.shop/api/v1/cart'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List items = data['data'] ?? [];
        if (mounted) {
          setState(() {
            _cartItemCount = items.length;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching cart count: $e");
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

  Widget _buildHomeContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                          fontSize: 14, color: Color(0xFF78716C), height: 1.2),
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
              const SizedBox(width: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_cart_outlined,
                        color: Color(0xFF292524), size: 26),
                    if (_cartItemCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFCF4173),
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '$_cartItemCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CartScreen(
                        baseUrl: 'https://dev.storkia.shop',
                        token: widget.token,
                      ),
                    ),
                  ).then((_) => _fetchCartItemCount());
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.chat_bubble_outline,
                    color: Color(0xFF292524), size: 26),
                onPressed: () {},
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading && !_isFetchingMore
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFCF4173)))
              : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                    _products.isEmpty
                        ? const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child:
                                  Center(child: Text('No products available.')),
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
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return BrowseScreen(token: widget.token);
      case 3:
        return MeScreen(user: widget.user, token: widget.token);
      default:
        return _buildHomeContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      body: SafeArea(
        child: _buildBody(),
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
