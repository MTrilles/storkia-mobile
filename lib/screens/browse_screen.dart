import 'package:flutter/material.dart';
import 'category_products_screen.dart';

class BrowseScreen extends StatelessWidget {
  final String token;

  BrowseScreen({super.key, required this.token});

  final List<Map<String, dynamic>> categories = [
    {
      'name': 'Pet',
      'icon': Icons.pets,
      'subcategories': [
        'Dog Food & Treats',
        'Cat Litter & Accessories',
        'Aquariums & Fish Supplies',
        'Bird Feeders & Food',
        'Pet Grooming Products',
        'Pet Health & Wellness'
      ]
    },
    {
      'name': 'Kids',
      'icon': Icons.child_care,
      'subcategories': [
        'Baby Clothes & Accessories',
        'Toys & Games',
        'Educational Materials',
        'Strollers & Gear',
        'Nursery Furniture',
        'Safety and Health'
      ]
    },
    {
      'name': 'Electronics',
      'icon': Icons.devices,
      'subcategories': [
        'Mobile Phones & Accessories',
        'Laptops, Desktops & Monitors',
        'Audio & Video Equipment',
        'Smart Home Devices',
        'Cameras & Photography',
        'Wearable Technology'
      ]
    },
    {
      'name': 'Home & Garden',
      'icon': Icons.home,
      'subcategories': [
        'Kitchen Appliances',
        'Furniture & Decor',
        'Gardening Tools',
        'Outdoor Living',
        'Home Improvement Tools',
        'Bedding & Bath'
      ]
    },
    {
      'name': 'Women\'s',
      'icon': Icons.woman,
      'subcategories': [
        'Dresses & Skirts',
        'Tops & Blouses',
        'Activewear & Yoga Pants',
        'Lingerie & Sleepwear',
        'Jackets & Coats',
        'Shoes & Accessories'
      ]
    },
    {
      'name': 'Men\'s',
      'icon': Icons.man,
      'subcategories': [
        'Suits & Blazers',
        'Casual Shirts & Pants',
        'Outerwear & Jackets',
        'Activewear & Fitness Gear',
        'Shoes & Accessories',
        'Grooming Products'
      ]
    },
    {
      'name': 'Health & Beauty',
      'icon': Icons.health_and_safety,
      'subcategories': [
        'Skincare Products',
        'Haircare Solutions',
        'Makeup & Cosmetics',
        'Personal Care Appliances',
        'Men\'s Grooming',
        'Health Supplements'
      ]
    },
    {
      'name': 'Books & Media',
      'icon': Icons.book,
      'subcategories': [
        'Fiction & Non-Fiction Books',
        'Magazines & Periodicals',
        'Music CDs & Vinyl Records',
        'Movie DVDs & Blu-ray',
        'Video Games & Consoles',
        'Educational DVDs'
      ]
    },
    {
      'name': 'Sports & Outdoors',
      'icon': Icons.sports_soccer,
      'subcategories': [
        'Fitness Equipment',
        'Camping & Hiking Gear',
        'Sports Apparel',
        'Cycling & Bikes',
        'Water Sports',
        'Team Sports Equipment'
      ]
    },
    {
      'name': 'Food & Gourmet',
      'icon': Icons.restaurant,
      'subcategories': [
        'Baking Supplies & Ingredients',
        'Coffee, Tea & Beverages',
        'Snacks & Candy',
        'Specialty Foods',
        'Organic and Health Foods',
        'Meal Kits & Prepped Foods'
      ]
    },
    {
      'name': 'Furniture & Office',
      'icon': Icons.chair,
      'subcategories': [
        'Office Desks & Chairs',
        'Storage Cabinets & Shelving',
        'Conference & Meeting Furniture',
        'Computer Tables & Workstations',
        'Ergonomic Accessories',
        'Office Lighting & Fixtures'
      ]
    },
    {
      'name': 'Jewelry & Watches',
      'icon': Icons.watch,
      'subcategories': [
        'Necklaces & Pendants',
        'Rings & Earrings',
        'Bracelets & Bangles',
        'Watches for Men & Women',
        'Fashion Jewelry',
        'Jewelry Storage & Care'
      ]
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
                        categoryName: category['name'],
                        subcategories: category['subcategories'],
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
