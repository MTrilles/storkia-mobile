import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../components/custom_bottom_nav.dart';
import '../components/daily_chest_floating_button.dart';
import '../components/product_card.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../models/seller_profile_model.dart';
import '../models/user_model.dart';
import '../providers/global_counters_provider.dart';
import '../services/api_service.dart';
import 'announcements_screen.dart';
import 'browse_screen.dart';
import 'bundle_deals_screen.dart';
import 'cart_screen.dart';
import 'category_products_screen.dart';
import 'me_screen.dart';
import 'messages_screen.dart';
import 'my_coupons_screen.dart';
import 'notifications_screen.dart';
import 'points_rewards_screen.dart';
import 'product_show.dart';
import 'search_screen.dart';
import 'seller_store_screen.dart';
import 'sellers_directory_screen.dart';
import 'super_deals_screen.dart';
import 'trends_screen.dart';

typedef JsonMap = Map<String, dynamic>;
typedef IntProductMap = Map<int, Product>;

class HomeScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final String token;
  final int initialIndex;

  const HomeScreen({
    super.key,
    required this.user,
    required this.token,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late int _currentIndex;
  final ScrollController _scrollController = ScrollController();
  final PageController _bannerController = PageController();
  Timer? _bannerTimer;
  Timer? _autoSyncTimer;
  int _activeBanner = 0;

  List<JsonMap> _apiBanners = [];
  List<JsonMap> _superDealItems = [];
  int _superDealsTotal = 0;
  List<JsonMap> _trendingItems = [];
  int _activeBundleCount = 0;

  List<Product> _products = [];
  List<Product> _youMayAlsoLike = [];
  List<Product> _dealsProducts = [];
  List<SellerProfile> _featuredSellers = [];

  bool _isLoading = true;
  bool _isFetchingMore = false;
  String? _errorMessage;
  int _currentPage = 1;
  bool _hasMore = true;

  final String _baseUrl = ApiConfig.domainUrl;

  final List<JsonMap> _fallbackHeroSlides = const [
    {
      'badge_text': 'CURATED MARKETPLACE',
      'title': 'Fast Delivery.\nExclusive Local Deals.',
      'subtitle':
          'Shop verified merchants with real-time QR package tracking to your doorstep.',
      'cta_text': 'Explore Deals',
      'cta_target': {'type': 'deals', 'value': null},
    },
    {
      'badge_text': 'DAILY REWARDS & COINS',
      'title': 'Open Your Daily Chest\n& Spin to Win Coins',
      'subtitle':
          'Redeem 10 Storkia Coins = ₱1.00 at checkout or unlock platform & shipping vouchers.',
      'cta_text': 'Open Rewards',
      'cta_target': {'type': 'rewards', 'value': null},
    },
    {
      'badge_text': 'STORKIA E-WALLET & COD',
      'title': 'Instant E-Wallet Checkout\n& Cash on Delivery',
      'subtitle':
          'Top up via GCash screenshot verification and enjoy 72-hour buyer protection.',
      'cta_text': 'Browse Bundles',
      'cta_target': {'type': 'bundles', 'value': null},
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _loadInitialHomeData();
    _scrollController.addListener(_onScroll);
    _startBannerAutoPlay();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      syncAllBuyerCounters(ref, widget.token);
    });

    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      syncAllBuyerCounters(ref, widget.token);
      if (_currentIndex == 0 && !_isLoading && !_isFetchingMore) {
        _fetchHomeFeedSilently();
        _fetchFirstPageProductsSilently();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncAllBuyerCounters(ref, widget.token);
      if (_currentIndex == 0) {
        _fetchHomeFeedSilently();
        _fetchFirstPageProductsSilently();
      }
    }
  }

  void _startBannerAutoPlay() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final slides = _apiBanners.isNotEmpty ? _apiBanners : _fallbackHeroSlides;
      if (!mounted ||
          !_bannerController.hasClients ||
          _currentIndex != 0 ||
          slides.isEmpty) {
        return;
      }
      final next = (_activeBanner + 1) % slides.length;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_currentIndex != 0) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      if (!_isFetchingMore && _hasMore && !_isLoading) {
        _fetchProducts(loadMore: true);
      }
    }
  }

  Future<void> _loadInitialHomeData({bool isRefresh = false}) async {
    await Future.wait([
      _fetchHomeFeedSilently(),
      _fetchProducts(isRefresh: isRefresh),
    ]);
  }

  Future<void> _fetchHomeFeedSilently() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/v1/home'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted || response.statusCode != 200) return;
      final body = json.decode(response.body);
      if (body is Map && body['success'] == true && body['data'] is Map) {
        final data = Map<String, dynamic>.from(body['data'] as Map);
        final List<dynamic> rawBanners = data['banners'] is List
            ? List<dynamic>.from(data['banners'] as List)
            : <dynamic>[];
        final JsonMap superDealsMap = data['super_deals'] is Map
            ? Map<String, dynamic>.from(data['super_deals'] as Map)
            : <String, dynamic>{};
        final List<dynamic> rawDealItems = superDealsMap['items'] is List
            ? List<dynamic>.from(superDealsMap['items'] as List)
            : <dynamic>[];
        final List<dynamic> rawTrending = data['trending'] is List
            ? List<dynamic>.from(data['trending'] as List)
            : <dynamic>[];
        final int unreadAnn =
            int.tryParse(data['unread_announcements']?.toString() ?? '0') ?? 0;

        ref.read(unreadAnnouncementProvider.notifier).updateCount(unreadAnn);

        if (mounted) {
          setState(() {
            _apiBanners = [
              for (final e in rawBanners)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
            _superDealItems = [
              for (final e in rawDealItems)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
            _superDealsTotal =
                int.tryParse(superDealsMap['total']?.toString() ?? '0') ??
                    _superDealItems.length;
            _trendingItems = [
              for (final e in rawTrending)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
            _activeBundleCount =
                int.tryParse(data['bundle_count']?.toString() ?? '0') ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchFirstPageProductsSilently() async {
    try {
      final result = await ApiService.getProducts(
        widget.token,
        page: 1,
        perPage: 10,
      );
      if (!mounted || result['success'] != true) return;

      final rawPayload = result['data'];
      final JsonMap paginatedData = rawPayload['data'] is Map
          ? Map<String, dynamic>.from(rawPayload['data'] as Map)
          : Map<String, dynamic>.from(rawPayload as Map);
      final List<dynamic> productsJson = paginatedData['data'] is List
          ? List<dynamic>.from(paginatedData['data'] as List)
          : <dynamic>[];
      final List<Product> firstPageProducts = [
        for (final json in productsJson)
          if (json is Map) Product.fromJson(Map<String, dynamic>.from(json)),
      ];

      final List<dynamic> sellersRaw = rawPayload['featured_sellers'] is List
          ? List<dynamic>.from(rawPayload['featured_sellers'] as List)
          : <dynamic>[];
      final List<dynamic> recsRaw = rawPayload['you_may_also_like'] is List
          ? List<dynamic>.from(rawPayload['you_may_also_like'] as List)
          : <dynamic>[];
      final List<dynamic> dealsRaw = rawPayload['deals'] is List
          ? List<dynamic>.from(rawPayload['deals'] as List)
          : <dynamic>[];

      setState(() {
        _featuredSellers = [
          for (final s in sellersRaw)
            if (s is Map) SellerProfile.fromJson(Map<String, dynamic>.from(s)),
        ];
        _youMayAlsoLike = [
          for (final p in recsRaw)
            if (p is Map) Product.fromJson(Map<String, dynamic>.from(p)),
        ];
        _dealsProducts = [
          for (final p in dealsRaw)
            if (p is Map) Product.fromJson(Map<String, dynamic>.from(p)),
        ];

        if (_products.isEmpty) {
          _products = firstPageProducts;
        } else {
          final IntProductMap freshById = {
            for (final p in firstPageProducts) p.id: p
          };
          for (int i = 0; i < _products.length; i++) {
            final updated = freshById[_products[i].id];
            if (updated != null) {
              _products[i] = updated;
            }
          }
          final existingIds = _products.map((p) => p.id).toSet();
          for (final item in firstPageProducts.reversed) {
            if (!existingIds.contains(item.id)) {
              _products.insert(0, item);
            }
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _fetchProducts({
    bool loadMore = false,
    bool isRefresh = false,
  }) async {
    if (loadMore) {
      setState(() => _isFetchingMore = true);
    } else {
      setState(() {
        if (!isRefresh) _isLoading = true;
        _errorMessage = null;
        _currentPage = 1;
        _hasMore = true;
      });
    }

    final result = await ApiService.getProducts(
      widget.token,
      page: _currentPage,
      perPage: 10,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final rawPayload = result['data'];
      final JsonMap paginatedData = rawPayload['data'] is Map
          ? Map<String, dynamic>.from(rawPayload['data'] as Map)
          : Map<String, dynamic>.from(rawPayload as Map);

      final List<dynamic> productsJson = paginatedData['data'] is List
          ? List<dynamic>.from(paginatedData['data'] as List)
          : <dynamic>[];
      final int lastPage =
          int.tryParse(paginatedData['last_page']?.toString() ?? '1') ?? 1;

      final List<Product> newProducts = [
        for (final json in productsJson)
          if (json is Map) Product.fromJson(Map<String, dynamic>.from(json)),
      ];

      if (!loadMore) {
        final List<dynamic> sellersRaw = rawPayload['featured_sellers'] is List
            ? List<dynamic>.from(rawPayload['featured_sellers'] as List)
            : <dynamic>[];
        final List<dynamic> recsRaw = rawPayload['you_may_also_like'] is List
            ? List<dynamic>.from(rawPayload['you_may_also_like'] as List)
            : <dynamic>[];
        final List<dynamic> dealsRaw = rawPayload['deals'] is List
            ? List<dynamic>.from(rawPayload['deals'] as List)
            : <dynamic>[];

        _featuredSellers = [
          for (final s in sellersRaw)
            if (s is Map) SellerProfile.fromJson(Map<String, dynamic>.from(s)),
        ];
        _youMayAlsoLike = [
          for (final p in recsRaw)
            if (p is Map) Product.fromJson(Map<String, dynamic>.from(p)),
        ];
        _dealsProducts = [
          for (final p in dealsRaw)
            if (p is Map) Product.fromJson(Map<String, dynamic>.from(p)),
        ];
      }

      setState(() {
        if (loadMore) {
          final existingIds = _products.map((p) => p.id).toSet();
          for (final item in newProducts) {
            if (!existingIds.contains(item.id)) {
              _products.add(item);
            }
          }
        } else {
          _products = newProducts;
        }

        if (_currentPage >= lastPage || newProducts.isEmpty) {
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
        if (_products.isEmpty) {
          _errorMessage = result['message']?.toString() ??
              'Unable to load products right now.';
        }
      });
    }
  }

  void _handleBannerTap(JsonMap slide) {
    final target = slide['cta_target'] is Map
        ? Map<String, dynamic>.from(slide['cta_target'] as Map)
        : <String, dynamic>{};
    final String type = target['type']?.toString() ?? '';
    final String? val = target['value']?.toString();

    switch (type) {
      case 'deals':
        Navigator.push(
          context,
          StorkRoute.fade(
            SuperDealsScreen(baseUrl: _baseUrl, token: widget.token),
          ),
        );
        break;
      case 'bundles':
        Navigator.push(
          context,
          StorkRoute.fade(
            BundleDealsScreen(baseUrl: _baseUrl, token: widget.token),
          ),
        );
        break;
      case 'trends':
        Navigator.push(
          context,
          StorkRoute.fade(
            TrendsScreen(baseUrl: _baseUrl, token: widget.token),
          ),
        );
        break;
      case 'announcements':
        Navigator.push(
          context,
          StorkRoute.fade(
            AnnouncementsScreen(baseUrl: _baseUrl, token: widget.token),
          ),
        );
        break;
      case 'sellers':
        Navigator.push(
          context,
          StorkRoute.fade(
            SellersDirectoryScreen(baseUrl: _baseUrl, token: widget.token),
          ),
        );
        break;
      case 'rewards':
        Navigator.push(
          context,
          StorkRoute.fade(
            PointsRewardsScreen(baseUrl: _baseUrl, token: widget.token),
          ),
        );
        break;
      case 'category':
        if (val != null && val.isNotEmpty) {
          Navigator.push(
            context,
            StorkRoute.fade(
              CategoryProductsScreen(
                slug: val,
                baseUrl: _baseUrl,
                token: widget.token,
              ),
            ),
          );
        }
        break;
      case 'search':
        Navigator.push(
          context,
          StorkRoute.fade(
            SearchScreen(baseUrl: _baseUrl, token: widget.token),
          ),
        );
        break;
      default:
        break;
    }
  }

  String _formatMoney(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  Widget _buildTopSearchBar(
    int cartItemCount,
    int unreadMessageCount,
    int unreadAnnouncementCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: StorkTheme.surface,
        border: Border(
          bottom: BorderSide(color: StorkTheme.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: StorkTheme.brandLight.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(
              'assets/icon.webp',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.storefront_rounded,
                color: StorkTheme.primary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  StorkRoute.fade(
                    SearchScreen(
                      baseUrl: _baseUrl,
                      token: widget.token,
                    ),
                  ),
                );
              },
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: StorkTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: StorkTheme.borderSubtle),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: StorkTheme.primary,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Search products, stores, deals...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _TopIconBadgeButton(
            icon: Icons.campaign_outlined,
            badgeCount: unreadAnnouncementCount,
            onTap: () {
              Navigator.push(
                context,
                StorkRoute.fade(
                  AnnouncementsScreen(
                    baseUrl: _baseUrl,
                    token: widget.token,
                  ),
                ),
              ).then((_) {
                ref
                    .read(unreadAnnouncementProvider.notifier)
                    .fetchUnreadCount(widget.token);
              });
            },
          ),
          _TopIconBadgeButton(
            icon: Icons.shopping_bag_outlined,
            badgeCount: cartItemCount,
            onTap: () {
              Navigator.push(
                context,
                StorkRoute.fade(
                  CartScreen(
                    baseUrl: _baseUrl,
                    token: widget.token,
                  ),
                ),
              ).then((_) {
                ref
                    .read(cartCountProvider.notifier)
                    .fetchCartCount(widget.token);
              });
            },
          ),
          _TopIconBadgeButton(
            icon: Icons.chat_bubble_outline_rounded,
            badgeCount: unreadMessageCount,
            onTap: () {
              Navigator.push(
                context,
                StorkRoute.fade(
                  MessagesScreen(
                    authUserId: widget.user.id,
                    token: widget.token,
                  ),
                ),
              ).then((_) {
                ref
                    .read(unreadMessageProvider.notifier)
                    .fetchUnreadCount(widget.token);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCarousel() {
    final slides = _apiBanners.isNotEmpty ? _apiBanners : _fallbackHeroSlides;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          SizedBox(
            height: 168,
            child: PageView.builder(
              controller: _bannerController,
              itemCount: slides.length,
              onPageChanged: (idx) => setState(() => _activeBanner = idx),
              itemBuilder: (context, index) {
                final slide = slides[index];
                final isEven = index % 2 == 0;
                final String badge = slide['badge_text']?.toString() ??
                    slide['badge']?.toString() ??
                    'STORKIA FEATURED';
                final String title = slide['title']?.toString() ?? '';
                final String subtitle = slide['subtitle']?.toString() ?? '';
                final String ctaText =
                    slide['cta_text']?.toString() ?? 'Shop Now';
                final String imageUrl = slide['image_url']?.toString() ?? '';

                return GestureDetector(
                  onTap: () => _handleBannerTap(slide),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        colors: isEven
                            ? const [StorkTheme.primaryDark, StorkTheme.primary]
                            : const [Color(0xFF292524), StorkTheme.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: StorkTheme.primaryDark.withValues(alpha: 0.16),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl.isNotEmpty)
                          Opacity(
                            opacity: 0.28,
                            child: Image.network(
                              ApiConfig.storageUrl(imageUrl, _baseUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  badge.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: StorkTheme.brandLight,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 11,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      ctaText,
                                      style: const TextStyle(
                                        color: StorkTheme.brandLight,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 13,
                                      color: StorkTheme.brandLight,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(slides.length, (i) {
              final active = i == _activeBanner;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 5,
                width: active ? 20 : 6,
                decoration: BoxDecoration(
                  color: active ? StorkTheme.primary : StorkTheme.borderSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickDiscoveryStrip(RewardSummaryState rewardState) {
    final List<JsonMap> items = [
      {
        'label': 'Super Deals',
        'sub': _superDealsTotal > 0 ? '$_superDealsTotal Live' : 'Flash Slots',
        'icon': Icons.bolt_rounded,
        'color': const Color(0xFFE11D48),
        'onTap': () {
          Navigator.push(
            context,
            StorkRoute.fade(
              SuperDealsScreen(baseUrl: _baseUrl, token: widget.token),
            ),
          );
        },
      },
      {
        'label': 'Bundle Deals',
        'sub': _activeBundleCount > 0
            ? '$_activeBundleCount Active'
            : 'Buy X Get Y',
        'icon': Icons.redeem_rounded,
        'color': const Color(0xFF7C3AED),
        'onTap': () {
          Navigator.push(
            context,
            StorkRoute.fade(
              BundleDealsScreen(baseUrl: _baseUrl, token: widget.token),
            ),
          );
        },
      },
      {
        'label': 'Trending',
        'sub': 'Top Picks',
        'icon': Icons.local_fire_department_rounded,
        'color': const Color(0xFFEA580C),
        'onTap': () {
          Navigator.push(
            context,
            StorkRoute.fade(
              TrendsScreen(baseUrl: _baseUrl, token: widget.token),
            ),
          );
        },
      },
      {
        'label': 'My Coins',
        'sub': '${rewardState.coinsBalance} Coins',
        'icon': Icons.monetization_on_rounded,
        'color': const Color(0xFFD97706),
        'onTap': () {
          Navigator.push(
            context,
            StorkRoute.fade(
              PointsRewardsScreen(
                baseUrl: _baseUrl,
                token: widget.token,
                initialTab: 0,
              ),
            ),
          );
        },
      },
      {
        'label': 'E-Wallet',
        'sub': '₱${_formatMoney(rewardState.walletAvailableBalance)}',
        'icon': Icons.account_balance_wallet_rounded,
        'color': StorkTheme.primaryDark,
        'onTap': () {
          Navigator.push(
            context,
            StorkRoute.fade(
              PointsRewardsScreen(
                baseUrl: _baseUrl,
                token: widget.token,
                initialTab: 1,
              ),
            ),
          );
        },
      },
      {
        'label': 'Vouchers',
        'sub': 'Claim Off',
        'icon': Icons.confirmation_number_outlined,
        'color': const Color(0xFF0D9488),
        'onTap': () {
          Navigator.push(
            context,
            StorkRoute.fade(
              MyCouponsScreen(baseUrl: _baseUrl, token: widget.token),
            ),
          );
        },
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            final Color color = item['color'] as Color;
            return InkWell(
              onTap: item['onTap'] as VoidCallback,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 98,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: StorkTheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: StorkTheme.borderSubtle),
                  boxShadow: StorkTheme.softCardShadow,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        item['icon'] as IconData,
                        color: color,
                        size: 19,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item['label'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.textMain,
                      ),
                    ),
                    Text(
                      item['sub'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSuperDealsSpotlightSection() {
    if (_superDealItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [StorkTheme.danger, StorkTheme.primary],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '⚡ SUPER DEALS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Limited Slot Offers',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    StorkRoute.fade(
                      SuperDealsScreen(baseUrl: _baseUrl, token: widget.token),
                    ),
                  );
                },
                child: const Text(
                  'See All →',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 234,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _superDealItems.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = _superDealItems[index];
              final prodMap = entry['product'] is Map
                  ? Map<String, dynamic>.from(entry['product'] as Map)
                  : entry;
              final product = Product.fromJson(prodMap);

              final double dealPrice = double.tryParse((entry['deal_price'] ??
                          entry['effective_price'] ??
                          product.discountedPrice)
                      .toString()) ??
                  product.discountedPrice;
              final double origPrice = double.tryParse(
                      (entry['original_price'] ??
                              entry['regular_price'] ??
                              product.price)
                          .toString()) ??
                  product.price;
              final double pct = double.tryParse(
                      (entry['discount_percentage'] ??
                              product.effectiveDiscountPercent)
                          .toString()) ??
                  0;
              final int flashQty =
                  int.tryParse(entry['flash_quantity']?.toString() ?? '0') ?? 0;
              final int soldQty =
                  int.tryParse(entry['sold_quantity']?.toString() ?? '0') ?? 0;
              final double soldRatio =
                  flashQty > 0 ? (soldQty / flashQty).clamp(0.0, 1.0) : 0.25;
              final String imgUrl = product.pictures.isNotEmpty
                  ? ApiConfig.storageUrl(product.pictures.first, _baseUrl)
                  : '';

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    StorkRoute.fade(
                      ProductShowScreen(
                        product: product,
                        baseUrl: _baseUrl,
                        token: widget.token,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 158,
                  decoration: BoxDecoration(
                    color: StorkTheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: StorkTheme.primary.withValues(alpha: 0.35),
                    ),
                    boxShadow: StorkTheme.softCardShadow,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              color: StorkTheme.surfaceSubtle,
                              child: imgUrl.isNotEmpty
                                  ? Image.network(imgUrl, fit: BoxFit.cover)
                                  : const Icon(
                                      Icons.inventory_2_outlined,
                                      color: StorkTheme.textMuted,
                                    ),
                            ),
                            if (pct > 0)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: StorkTheme.danger,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '⚡ -${pct.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: StorkTheme.textMain,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '₱${_formatMoney(dealPrice)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w900,
                                      color: StorkTheme.price,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '₱${_formatMoney(origPrice)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      decoration: TextDecoration.lineThrough,
                                      color: StorkTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: soldRatio,
                                minHeight: 10,
                                backgroundColor:
                                    StorkTheme.primary.withValues(alpha: 0.14),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  StorkTheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              flashQty > 0
                                  ? '$soldQty / $flashQty Slot Sold'
                                  : 'Limited Time Deal',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: StorkTheme.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrendingSpotlightSection() {
    if (_trendingItems.isEmpty) return const SizedBox.shrink();

    final trendingProducts = _trendingItems
        .map((item) {
          final pMap = item['product'] is Map
              ? Map<String, dynamic>.from(item['product'] as Map)
              : item;
          return Product.fromJson(pMap);
        })
        .where((p) => p.id > 0)
        .toList();

    if (trendingProducts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    color: Color(0xFFEA580C),
                    size: 20,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Trending Now',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primaryDark,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    StorkRoute.fade(
                      TrendsScreen(baseUrl: _baseUrl, token: widget.token),
                    ),
                  );
                },
                child: const Text(
                  'View Rankings →',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 242,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: trendingProducts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 160,
                child: ProductCard(
                  product: trendingProducts[index],
                  baseUrl: _baseUrl,
                  token: widget.token,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedSellersSection() {
    if (_featuredSellers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'OUR OFFICIAL SELLERS',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: StorkTheme.primaryDark,
                  letterSpacing: 0.5,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    StorkRoute.fade(
                      SellersDirectoryScreen(
                        baseUrl: _baseUrl,
                        token: widget.token,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'All Verified Stores →',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 114,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _featuredSellers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final seller = _featuredSellers[index];
              final logoUrl = seller.logoPath != null
                  ? ApiConfig.storageUrl(seller.logoPath, _baseUrl)
                  : '';

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    StorkRoute.fade(
                      SellerStoreScreen(
                        sellerProfile: seller,
                        baseUrl: _baseUrl,
                        token: widget.token,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 156,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StorkTheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: StorkTheme.borderSubtle),
                    boxShadow: StorkTheme.softCardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                StorkTheme.primary.withValues(alpha: 0.12),
                            backgroundImage: logoUrl.isNotEmpty
                                ? NetworkImage(logoUrl)
                                : null,
                            child: logoUrl.isEmpty
                                ? Text(
                                    seller.businessName.isNotEmpty
                                        ? seller.businessName[0].toUpperCase()
                                        : 'S',
                                    style: const TextStyle(
                                      color: StorkTheme.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              seller.businessName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.textMain,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        seller.lineOfBusiness.isNotEmpty
                            ? seller.lineOfBusiness
                            : '${seller.municipality}, ${seller.province}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalProductSection({
    required String badge,
    required String title,
    required List<Product> items,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: StorkTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: StorkTheme.primaryDark,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 242,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 160,
                child: ProductCard(
                  product: items[index],
                  baseUrl: _baseUrl,
                  token: widget.token,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHomeContent() {
    final cartItemCount = ref.watch(cartCountProvider);
    final unreadMessageCount = ref.watch(unreadMessageProvider);
    final unreadAnnouncementCount = ref.watch(unreadAnnouncementProvider);
    final rewardState = ref.watch(rewardSummaryProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final gridCols = screenWidth >= 700 ? 3 : 2;
    final aspectRatio = screenWidth < 350 ? 0.63 : 0.68;

    return Stack(
      children: [
        Column(
          children: [
            _buildTopSearchBar(
              cartItemCount,
              unreadMessageCount,
              unreadAnnouncementCount,
            ),
            Expanded(
              child: _isLoading && !_isFetchingMore
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: StorkTheme.primary),
                    )
                  : _errorMessage != null && _products.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.wifi_off_rounded,
                                  size: 48,
                                  color: StorkTheme.textMuted,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: StorkTheme.textMain,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _loadInitialHomeData(),
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: StorkTheme.primary,
                          onRefresh: () =>
                              _loadInitialHomeData(isRefresh: true),
                          child: CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildHeroCarousel(),
                                    _buildQuickDiscoveryStrip(rewardState),
                                    _buildSuperDealsSpotlightSection(),
                                    _buildTrendingSpotlightSection(),
                                    _buildFeaturedSellersSection(),
                                    if (_dealsProducts.isNotEmpty &&
                                        _superDealItems.isEmpty)
                                      _buildHorizontalProductSection(
                                        badge: 'LIMITED OFFERS',
                                        title: 'Deals & Promotions',
                                        items: _dealsProducts,
                                      ),
                                    if (_youMayAlsoLike.isNotEmpty)
                                      _buildHorizontalProductSection(
                                        badge: 'PERSONALIZED PICKS',
                                        title: 'You May Also Like',
                                        items: _youMayAlsoLike,
                                      ),
                                    const Padding(
                                      padding:
                                          EdgeInsets.fromLTRB(16, 20, 16, 10),
                                      child: Text(
                                        'Picked For You (All Products)',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: StorkTheme.primaryDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _products.isEmpty
                                  ? const SliverToBoxAdapter(
                                      child: Padding(
                                        padding: EdgeInsets.all(40.0),
                                        child: Center(
                                          child: Text(
                                            'No products available right now.',
                                            style: TextStyle(
                                                color: StorkTheme.textMuted),
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
                                          crossAxisCount: gridCols,
                                          childAspectRatio: aspectRatio,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                            return ProductCard(
                                              product: _products[index],
                                              baseUrl: _baseUrl,
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
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 92)),
                            ],
                          ),
                        ),
            ),
          ],
        ),
        Positioned(
          right: 14,
          bottom: 14,
          child: DailyChestFloatingButton(
            baseUrl: _baseUrl,
            token: widget.token,
            onOpenRewardsHub: () {
              Navigator.push(
                context,
                StorkRoute.fade(
                  PointsRewardsScreen(
                    baseUrl: _baseUrl,
                    token: widget.token,
                    initialTab: 0,
                  ),
                ),
              );
            },
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
        return BrowseScreen(token: widget.token, baseUrl: _baseUrl);
      case 2:
        return NotificationsScreen(baseUrl: _baseUrl, token: widget.token);
      case 3:
        return MeScreen(
          user: widget.user,
          token: widget.token,
          baseUrl: _baseUrl,
        );
      default:
        return _buildHomeContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadNotifications = ref.watch(unreadNotificationProvider);

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      body: SafeArea(
        child: _buildBody(),
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        unreadNotifications: unreadNotifications,
        onTap: (index) {
          if (_currentIndex == index) return;
          setState(() {
            _currentIndex = index;
          });
          syncAllBuyerCounters(ref, widget.token);
        },
      ),
    );
  }
}

class _TopIconBadgeButton extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  final VoidCallback onTap;

  const _TopIconBadgeButton({
    required this.icon,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: StorkTheme.primaryDark, size: 22),
          if (badgeCount > 0)
            Positioned(
              right: -5,
              top: -5,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: StorkTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: StorkTheme.surface, width: 1.5),
                ),
                constraints: const BoxConstraints(minWidth: 16),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
