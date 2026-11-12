import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/recently_viewed_service.dart';
import '../components/product_card.dart';

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
    setState(() {
      _products = products;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF292524),
        elevation: 0.5,
        title: const Text('Recently Viewed',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFCF4173)))
          : _products.isEmpty
              ? const Center(
                  child: Text('No recently viewed items.',
                      style: TextStyle(color: Color(0xFF78716C))))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.7,
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
    );
  }
}
