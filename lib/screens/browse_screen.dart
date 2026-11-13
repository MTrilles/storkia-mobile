import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import 'category_products_screen.dart';
import 'search_screen.dart';
import 'sellers_directory_screen.dart';

typedef CategoryMap = Map<String, dynamic>;

class BrowseScreen extends StatelessWidget {
  final String token;
  final String baseUrl;

  const BrowseScreen({
    super.key,
    required this.token,
    this.baseUrl = ApiConfig.domainUrl,
  });

  static const List<CategoryMap> categories = [
    {
      'name': 'Pet',
      'slug': 'pet',
      'subtitle': 'Food, litter & grooming',
      'icon': Icons.pets_rounded,
    },
    {
      'name': 'Kids',
      'slug': 'kids',
      'subtitle': 'Baby gear, toys & clothes',
      'icon': Icons.child_care_rounded,
    },
    {
      'name': 'Electronics',
      'slug': 'electronics',
      'subtitle': 'Phones, laptops & audio',
      'icon': Icons.devices_rounded,
    },
    {
      'name': 'Home & Garden',
      'slug': 'home-garden',
      'subtitle': 'Kitchen, decor & tools',
      'icon': Icons.chair_outlined,
    },
    {
      'name': 'Women\'s',
      'slug': 'womens',
      'subtitle': 'Dresses, tops & shoes',
      'icon': Icons.checkroom_rounded,
    },
    {
      'name': 'Men\'s',
      'slug': 'mens',
      'subtitle': 'Shirts, activewear & gear',
      'icon': Icons.dry_cleaning_rounded,
    },
    {
      'name': 'Health & Beauty',
      'slug': 'health-beauty',
      'subtitle': 'Skincare, hair & makeup',
      'icon': Icons.spa_outlined,
    },
    {
      'name': 'Books & Media',
      'slug': 'books-media',
      'subtitle': 'Books, music & gaming',
      'icon': Icons.menu_book_rounded,
    },
    {
      'name': 'Sports & Outdoors',
      'slug': 'sports-outdoors',
      'subtitle': 'Fitness, camping & cycling',
      'icon': Icons.sports_basketball_outlined,
    },
    {
      'name': 'Food & Gourmet',
      'slug': 'food-gourmet',
      'subtitle': 'Coffee, snacks & organic',
      'icon': Icons.bakery_dining_outlined,
    },
    {
      'name': 'Furniture & Office',
      'slug': 'furniture-office',
      'subtitle': 'Desks, chairs & lighting',
      'icon': Icons.desk_rounded,
    },
    {
      'name': 'Jewelry & Watches',
      'slug': 'jewelry-watches',
      'subtitle': 'Necklaces, rings & watches',
      'icon': Icons.watch_outlined,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final domain = ApiConfig.resolveBaseDomain(baseUrl);
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 700 ? 4 : (width >= 480 ? 3 : 2);
    final aspectRatio = width < 350 ? 1.18 : 1.32;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: StorkTheme.surface,
            border: Border(
              bottom: BorderSide(color: StorkTheme.borderSubtle, width: 1),
            ),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Browse Categories',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: StorkTheme.primaryDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Explore 12 curated department catalogs',
                      style: TextStyle(
                        fontSize: 12,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: StorkTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      StorkRoute.fade(
                        SearchScreen(baseUrl: domain, token: token),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      Icons.search_rounded,
                      color: StorkTheme.primaryDark,
                      size: 21,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        StorkRoute.fade(
                          SellersDirectoryScreen(
                            baseUrl: domain,
                            token: token,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: StorkTheme.brandGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                StorkTheme.primaryDark.withValues(alpha: 0.16),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Explore Official Stores',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Filter verified merchants by category or A–Z index',
                                  style: TextStyle(
                                    color: StorkTheme.brandLight,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: aspectRatio,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final category = categories[index];
                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            StorkRoute.fade(
                              CategoryProductsScreen(
                                slug: category['slug'] as String,
                                baseUrl: domain,
                                token: token,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: StorkTheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: StorkTheme.borderSubtle),
                            boxShadow: StorkTheme.softCardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          StorkTheme.primary
                                              .withValues(alpha: 0.16),
                                          StorkTheme.brandLight
                                              .withValues(alpha: 0.35),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      category['icon'] as IconData,
                                      size: 21,
                                      color: StorkTheme.primaryDark,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.north_east_rounded,
                                    size: 15,
                                    color: StorkTheme.textMuted,
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    category['name'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: StorkTheme.textMain,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    category['subtitle'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: StorkTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: categories.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
