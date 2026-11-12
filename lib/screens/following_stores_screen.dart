import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/seller_profile_model.dart';
import 'seller_store_screen.dart';
import 'sellers_directory_screen.dart';

typedef JsonMap = Map<String, dynamic>;

class FollowingStoresScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const FollowingStoresScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<FollowingStoresScreen> createState() => _FollowingStoresScreenState();
}

class _FollowingStoresScreenState extends State<FollowingStoresScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  List<JsonMap> _follows = [];
  Timer? _autoSyncTimer;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchFollowing();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _fetchFollowing(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchFollowing(silent: true);
    }
  }

  Future<void> _fetchFollowing({bool silent = false}) async {
    if (!silent && _follows.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/following'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && (data['success'] == true || data['data'] != null)) {
          List<dynamic> rawList = [];
          final d = data['data'];
          if (d is List) {
            rawList = d;
          } else if (d is Map) {
            final nested =
                d['following'] ?? d['sellers'] ?? d['items'] ?? d['data'];
            if (nested is List) {
              rawList = nested;
            }
          }
          setState(() {
            _follows = [
              for (final e in rawList)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
            _isLoading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unfollowStore(int sellerId, int index) async {
    setState(() {
      if (index >= 0 && index < _follows.length) {
        _follows.removeAt(index);
      }
    });
    try {
      await http.post(
        Uri.parse('$_domain/api/v1/sellers/$sellerId/follow'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);
      if (mounted) {
        _fetchFollowing(silent: true);
      }
    } catch (_) {
      if (mounted) {
        _fetchFollowing(silent: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Following Stores'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchFollowing(silent: true),
              child: _follows.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 80),
                        const Icon(
                          Icons.storefront_outlined,
                          size: 56,
                          color: StorkTheme.textMuted,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'You are not following any stores yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Follow your favorite verified merchants to automatically receive a 1-time ₱30 OFF Store Follower Welcome Voucher in your wallet!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: StorkTheme.textMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                StorkRoute.fade(
                                  SellersDirectoryScreen(
                                    baseUrl: _domain,
                                    token: widget.token,
                                  ),
                                ),
                              ).then((_) => _fetchFollowing(silent: true));
                            },
                            child: const Text('Explore Official Stores'),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _follows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = _follows[index];
                        final JsonMap sellerMap = item['seller_profile'] is Map
                            ? Map<String, dynamic>.from(
                                item['seller_profile'] as Map)
                            : (item['seller'] is Map
                                ? Map<String, dynamic>.from(
                                    item['seller'] as Map)
                                : item);
                        final seller = SellerProfile.fromJson(sellerMap);
                        final stats = seller.stats ??
                            (item['stats'] is Map
                                ? Map<String, dynamic>.from(
                                    item['stats'] as Map)
                                : <String, dynamic>{});
                        final rewardCode = (item['reward_voucher_code'] ??
                                sellerMap['reward_voucher_code'])
                            ?.toString();
                        final logoUrl = (seller.logoPath != null &&
                                seller.logoPath!.trim().isNotEmpty)
                            ? ApiConfig.storageUrl(seller.logoPath, _domain)
                            : '';

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: StorkTheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: StorkTheme.borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: StorkTheme.primary
                                        .withValues(alpha: 0.12),
                                    backgroundImage: logoUrl.isNotEmpty
                                        ? NetworkImage(logoUrl)
                                        : null,
                                    child: logoUrl.isEmpty
                                        ? Text(
                                            seller.businessName.isNotEmpty
                                                ? seller.businessName[0]
                                                    .toUpperCase()
                                                : 'S',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: StorkTheme.primary,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          seller.businessName,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: StorkTheme.textMain,
                                          ),
                                        ),
                                        Text(
                                          [
                                            if (seller
                                                .lineOfBusiness.isNotEmpty)
                                              seller.lineOfBusiness,
                                            if (seller
                                                    .municipality.isNotEmpty ||
                                                seller.province.isNotEmpty)
                                              '${seller.municipality}, ${seller.province}',
                                          ].join(' • '),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: StorkTheme.textMuted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Rating: ${stats['ratings'] ?? '0.0'} • Followers: ${stats['followers'] ?? 0} • Chat: ${stats['chat_response_rate'] ?? 98}%',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: StorkTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (rewardCode != null &&
                                  rewardCode.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: StorkTheme.brandLight
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: StorkTheme.borderSubtle),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '1-TIME FOLLOWER REWARD VOUCHER',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: StorkTheme.primaryDark,
                                            ),
                                          ),
                                          Text(
                                            '$rewardCode (₱30 OFF • Min. ₱150)',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: StorkTheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Text(
                                        'In Wallet',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: StorkTheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Divider(height: 22),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        StorkRoute.fade(
                                          SellerStoreScreen(
                                            sellerProfile: seller,
                                            baseUrl: _domain,
                                            token: widget.token,
                                          ),
                                        ),
                                      ).then(
                                          (_) => _fetchFollowing(silent: true));
                                    },
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                    ),
                                    child: const Text('Visit Store'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () =>
                                        _unfollowStore(seller.id, index),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: StorkTheme.danger,
                                      side: BorderSide(
                                        color: StorkTheme.danger
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: const Text('Unfollow'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
