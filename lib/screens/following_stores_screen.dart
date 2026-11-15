import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/seller_profile_model.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
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
  Timer? _wsDebounceTimer;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchFollowing();
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'catalog' ||
        event.scope == 'marketplace' ||
        event.scope == 'voucher') {
      _wsDebounceTimer?.cancel();
      _wsDebounceTimer = Timer(const Duration(milliseconds: 280), () {
        if (mounted) {
          _fetchFollowing(silent: true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsDebounceTimer?.cancel();
    WebSocketService.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchFollowing(silent: true);
    }
  }

  void _showPopupToast(String message, {bool isError = false}) {
    if (!mounted || message.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.trim(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        backgroundColor: isError ? StorkTheme.danger : StorkTheme.success,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Future<void> _fetchFollowing({bool silent = false}) async {
    if (!silent && _follows.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('$_domain/api/v1/following'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

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
      await ApiService.httpClient
          .post(
            Uri.parse('$_domain/api/v1/sellers/$sellerId/follow'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);
      if (mounted) {
        _showPopupToast('Unfollowed store.', isError: false);
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
        title: Text('Following Stores (${_follows.length})'),
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
                        Center(
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              color: StorkTheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.storefront_outlined,
                              size: 38,
                              color: StorkTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'You Are Not Following Any Stores Yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
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
                        const SizedBox(height: 20),
                        Center(
                          child: ElevatedButton.icon(
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
                            icon:
                                const Icon(Icons.storefront_rounded, size: 18),
                            label: const Text('Explore Official Stores'),
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
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: StorkTheme.borderSubtle),
                            boxShadow: StorkTheme.softCardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: StorkTheme.primary
                                            .withValues(alpha: 0.25),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: CircleAvatar(
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          seller.businessName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: StorkTheme.primaryDark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: StorkTheme.textMuted,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            _buildStatChip(
                                              '${stats['ratings'] ?? '0.0'} ★',
                                            ),
                                            _buildStatChip(
                                              '${stats['followers'] ?? 0} Followers',
                                            ),
                                            _buildStatChip(
                                              '${stats['chat_response_rate'] ?? 98}% Chat',
                                            ),
                                          ],
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
                                      horizontal: 12, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: StorkTheme.brandLight
                                        .withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: StorkTheme.primary
                                          .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '1-TIME FOLLOWER REWARD VOUCHER',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w900,
                                                color: StorkTheme.primaryDark,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
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
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: StorkTheme.primary,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'In Wallet',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Divider(height: 22),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
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
                                        ).then((_) =>
                                            _fetchFollowing(silent: true));
                                      },
                                      icon: const Icon(
                                        Icons.storefront_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('Visit Store'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 11),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton(
                                    onPressed: () =>
                                        _unfollowStore(seller.id, index),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: StorkTheme.danger,
                                      side: BorderSide(
                                        color: StorkTheme.danger
                                            .withValues(alpha: 0.4),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 11),
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

  Widget _buildStatChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: StorkTheme.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: StorkTheme.primaryDark,
        ),
      ),
    );
  }
}
