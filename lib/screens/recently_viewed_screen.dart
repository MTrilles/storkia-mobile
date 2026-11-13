import 'package:flutter/material.dart';
import '../components/product_card.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../services/recently_viewed_service.dart';

class RecentlyViewedScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const RecentlyViewedScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<RecentlyViewedScreen> createState() => _RecentlyViewedScreenState();
}

class _RecentlyViewedScreenState extends State<RecentlyViewedScreen> {
  List<Product> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await RecentlyViewedService.getProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth >= 700 ? 3 : 2;
    final aspectRatio = screenWidth < 350 ? 0.63 : 0.68;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text('Recently Viewed (${_products.length})'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: _loadProducts,
              child: _products.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 90),
                        Center(
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: StorkTheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.history_rounded,
                              size: 38,
                              color: StorkTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Recently Viewed Products Yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Products you view while browsing Storkia will automatically appear here for quick access.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: StorkTheme.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: aspectRatio,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _products.length,
                      itemBuilder: (context, index) {
                        return ProductCard(
                          product: _products[index],
                          baseUrl: widget.baseUrl,
                          token: widget.token,
                        );
                      },
                    ),
            ),
    );
  }
}
