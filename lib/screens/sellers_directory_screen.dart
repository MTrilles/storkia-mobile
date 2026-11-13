import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/seller_profile_model.dart';
import 'seller_store_screen.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef IntBoolMap = Map<int, bool>;
typedef IntIntMap = Map<int, int>;

class SellersDirectoryScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const SellersDirectoryScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<SellersDirectoryScreen> createState() => _SellersDirectoryScreenState();
}

class _SellersDirectoryScreenState extends State<SellersDirectoryScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  Timer? _autoSyncTimer;

  bool _isLoading = true;
  List<SellerProfile> _allSellers = [];
  final IntBoolMap _followOverrides = {};
  final IntIntMap _followerCountOverrides = {};
  final Set<int> _togglingIds = <int>{};

  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedLetter = 'ALL';

  static const List<String> _alphabet = [
    'ALL',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '#',
  ];

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchSellers(silent: false);
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_togglingIds.isEmpty) {
        _fetchSellers(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchSellers(silent: true);
    }
  }

  JsonList _extractSellersList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) JsonMap.from(item),
      ];
    }
    if (raw is Map) {
      for (final key in ['sellers', 'stores', 'items', 'data']) {
        if (raw.containsKey(key) && raw[key] != null && raw[key] != raw) {
          final extracted = _extractSellersList(raw[key]);
          if (extracted.isNotEmpty) return extracted;
        }
      }
      for (final value in raw.values) {
        if (value is List) {
          final extracted = _extractSellersList(value);
          if (extracted.isNotEmpty) return extracted;
        }
      }
    }
    return [];
  }

  Future<void> _fetchSellers({bool silent = true}) async {
    if (!silent && _allSellers.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/sellers'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final rawList = _extractSellersList(
          body is Map ? (body['data'] ?? body) : body,
        );
        final parsed = [
          for (final s in rawList) SellerProfile.fromJson(s),
        ];
        setState(() {
          _allSellers = parsed;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow(SellerProfile seller) async {
    if (_togglingIds.contains(seller.id) || seller.isOwnStore) return;

    final bool currentFollow =
        _followOverrides[seller.id] ?? seller.isFollowing;
    final int baseFollowers =
        int.tryParse(seller.stats?['followers']?.toString() ?? '0') ?? 0;
    final int currentFollowers =
        _followerCountOverrides[seller.id] ?? baseFollowers;

    setState(() {
      _togglingIds.add(seller.id);
      _followOverrides[seller.id] = !currentFollow;
      _followerCountOverrides[seller.id] = !currentFollow
          ? currentFollowers + 1
          : (currentFollowers > 0 ? currentFollowers - 1 : 0);
    });

    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/sellers/${seller.id}/follow'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        setState(() {
          if (data['is_following'] is bool) {
            _followOverrides[seller.id] = data['is_following'] as bool;
          }
          if (data['followers_count'] != null) {
            _followerCountOverrides[seller.id] =
                int.tryParse(data['followers_count'].toString()) ??
                    _followerCountOverrides[seller.id]!;
          }
        });
        if (data['message'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'].toString()),
              backgroundColor: StorkTheme.success,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        setState(() {
          _followOverrides[seller.id] = currentFollow;
          _followerCountOverrides[seller.id] = currentFollowers;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _followOverrides[seller.id] = currentFollow;
          _followerCountOverrides[seller.id] = currentFollowers;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _togglingIds.remove(seller.id));
      }
    }
  }

  List<String> get _categories {
    final Set<String> cats = <String>{'All'};
    for (final s in _allSellers) {
      if (s.lineOfBusiness.trim().isNotEmpty) {
        cats.add(s.lineOfBusiness.trim());
      }
    }
    return cats.toList();
  }

  List<SellerProfile> get _filteredSellers {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _allSellers.where((s) {
      if (_selectedCategory != 'All' &&
          s.lineOfBusiness.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }
      if (_selectedLetter != 'ALL') {
        final firstChar = s.businessName.trim().isNotEmpty
            ? s.businessName.trim()[0].toUpperCase()
            : '';
        if (_selectedLetter == '#') {
          if (RegExp(r'^[A-Z]$').hasMatch(firstChar)) return false;
        } else if (firstChar != _selectedLetter) {
          return false;
        }
      }
      if (q.isNotEmpty) {
        final hay =
            '${s.businessName} ${s.lineOfBusiness} ${s.municipality} ${s.province}'
                .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) =>
        a.businessName.toLowerCase().compareTo(b.businessName.toLowerCase()));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final visibleSellers = _filteredSellers;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text('Official Stores (${_allSellers.length})'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: const BoxDecoration(
              color: StorkTheme.surface,
              border: Border(
                bottom: BorderSide(color: StorkTheme.borderSubtle),
              ),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search verified stores, category, or city...',
                    fillColor: StorkTheme.surfaceSubtle,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: StorkTheme.primary,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.clear_rounded, size: 18),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      final active = _selectedCategory == cat;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: active ? StorkTheme.brandGradient : null,
                            color: active ? null : StorkTheme.surfaceSubtle,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: active
                                  ? StorkTheme.primary
                                  : StorkTheme.borderSubtle,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color:
                                  active ? Colors.white : StorkTheme.textMain,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 28,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _alphabet.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final letter = _alphabet[index];
                      final active = _selectedLetter == letter;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedLetter = letter),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active
                                ? StorkTheme.primaryDark
                                : StorkTheme.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            letter,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color:
                                  active ? Colors.white : StorkTheme.textMuted,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading && _allSellers.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: StorkTheme.primary),
                  )
                : RefreshIndicator(
                    color: StorkTheme.primary,
                    onRefresh: () => _fetchSellers(silent: true),
                    child: visibleSellers.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(28),
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Container(
                                  width: 74,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    color: StorkTheme.primary
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.storefront_outlined,
                                    size: 36,
                                    color: StorkTheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No Verified Stores Match Your Filter',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Try selecting "ALL" letters or clearing your search filter.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: StorkTheme.textMuted,
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(14),
                            itemCount: visibleSellers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return _buildSellerCard(visibleSellers[index]);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerCard(SellerProfile seller) {
    final String logoUrl =
        (seller.logoPath != null && seller.logoPath!.trim().isNotEmpty)
            ? ApiConfig.storageUrl(seller.logoPath, _domain)
            : '';
    final bool isFollowing = _followOverrides[seller.id] ?? seller.isFollowing;
    final stats = seller.stats ?? <String, dynamic>{};
    final int followers = _followerCountOverrides[seller.id] ??
        (int.tryParse(stats['followers']?.toString() ?? '0') ?? 0);
    final String rating = stats['ratings']?.toString() ?? '0.0';
    final int productsCount =
        int.tryParse(stats['products_count']?.toString() ?? '0') ?? 0;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          StorkRoute.fade(
            SellerStoreScreen(
              sellerProfile: seller,
              baseUrl: _domain,
              token: widget.token,
            ),
          ),
        ).then((_) => _fetchSellers(silent: true));
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: StorkTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: StorkTheme.borderSubtle),
          boxShadow: StorkTheme.softCardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: StorkTheme.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: StorkTheme.primary.withValues(alpha: 0.12),
                backgroundImage:
                    logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                child: logoUrl.isEmpty
                    ? Text(
                        seller.businessName.isNotEmpty
                            ? seller.businessName[0].toUpperCase()
                            : 'S',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: StorkTheme.primary,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          seller.businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                      ),
                      if (seller.isOnVacation) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: StorkTheme.warning.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ON VACATION',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (seller.lineOfBusiness.isNotEmpty)
                        seller.lineOfBusiness,
                      if (seller.municipality.isNotEmpty ||
                          seller.province.isNotEmpty)
                        '${seller.municipality}, ${seller.province}',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: StorkTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildMiniStatPill('★ $rating'),
                      _buildMiniStatPill('$followers Followers'),
                      _buildMiniStatPill('$productsCount Products'),
                    ],
                  ),
                ],
              ),
            ),
            if (!seller.isOwnStore) ...[
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _togglingIds.contains(seller.id)
                    ? null
                    : () => _toggleFollow(seller),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFollowing
                      ? StorkTheme.surfaceSubtle
                      : StorkTheme.primary,
                  foregroundColor:
                      isFollowing ? StorkTheme.textMain : Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 34),
                ),
                child: Text(
                  isFollowing ? 'Following' : '+ Follow',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStatPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: StorkTheme.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: StorkTheme.primaryDark,
        ),
      ),
    );
  }
}
