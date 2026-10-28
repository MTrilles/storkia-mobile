import 'package:flutter/material.dart';
import 'category_products_screen.dart';

class BrowseScreen extends StatelessWidget {
  final String token;
  final String baseUrl; // Added to pass down to CategoryProductsScreen

  BrowseScreen(
      {super.key,
      required this.token,
      this.baseUrl = 'https://dev.storkia.shop'});

  final List<Map<String, dynamic>> categories = [
    {
      'name': 'Pet',
      'slug': 'pet',
      'icon': Icons.pets,
    },
    {
      'name': 'Kids',
      'slug': 'kids',
      'icon': Icons.child_care,
    },
    {
      'name': 'Electronics',
      'slug': 'electronics',
      'icon': Icons.devices,
    },
    {
      'name': 'Home & Garden',
      'slug': 'home-garden',
      'icon': Icons.home,
    },
    {
      'name': 'Women\'s',
      'slug': 'womens',
      'icon': Icons.woman,
    },
    {
      'name': 'Men\'s',
      'slug': 'mens',
      'icon': Icons.man,
    },
    {
      'name': 'Health & Beauty',
      'slug': 'health-beauty',
      'icon': Icons.health_and_safety,
    },
    {
      'name': 'Books & Media',
      'slug': 'books-media',
      'icon': Icons.book,
    },
    {
      'name': 'Sports & Outdoors',
      'slug': 'sports-outdoors',
      'icon': Icons.sports_soccer,
    },
    {
      'name': 'Food & Gourmet',
      'slug': 'food-gourmet',
      'icon': Icons.restaurant,
    },
    {
      'name': 'Furniture & Office',
      'slug': 'furniture-office',
      'icon': Icons.chair,
    },
    {
      'name': 'Jewelry & Watches',
      'slug': 'jewelry-watches',
      'icon': Icons.watch,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          width: double.infinity,
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
          child: const Text(
            'Browse Categories',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF292524),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.85,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CategoryProductsScreen(
                        slug: category[
                            'slug'], // Pass slug instead of categoryName
                        baseUrl: baseUrl, // Pass baseUrl
                        token: token,
                      ),
                    ),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 60,
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Icon(
                        category['icon'],
                        size: 32,
                        color: const Color(0xFFCF4173),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      category['name'],
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF292524),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
