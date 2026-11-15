import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/global_counters_provider.dart';
import '../services/websocket_service.dart';
import 'account_management_screen.dart';
import 'address_selection_screen.dart';
import 'announcements_screen.dart';
import 'bundle_deals_screen.dart';
import 'following_stores_screen.dart';
import 'help_center_screen.dart';
import 'identity_verification_screen.dart';
import 'legal_policies_screen.dart';
import 'login_screen.dart';
import 'my_coupons_screen.dart';
import 'orders_screen.dart';
import 'points_rewards_screen.dart';
import 'profile_screen.dart';
import 'recently_viewed_screen.dart';
import 'seller_reports_screen.dart';
import 'super_deals_screen.dart';
import 'wishlist_screen.dart';

class MeScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final String token;
  final String baseUrl;

  const MeScreen({
    super.key,
    required this.user,
    required this.token,
    this.baseUrl = ApiConfig.domainUrl,
  });

  @override
  ConsumerState<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends ConsumerState<MeScreen>
    with WidgetsBindingObserver {
  Timer? _wsDebounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).refreshUserProfile();
      syncAllBuyerCounters(ref, widget.token);
    });
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    _wsDebounceTimer?.cancel();
    _wsDebounceTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted) {
        ref.read(authProvider.notifier).refreshUserProfile();
        syncAllBuyerCounters(ref, widget.token);
      }
    });
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
      ref.read(authProvider.notifier).refreshUserProfile();
      syncAllBuyerCounters(ref, widget.token);
    }
  }

  String _formatMoney(double val) {
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: StorkTheme.primary),
              SizedBox(width: 8),
              Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          content: const Text(
            'Are you sure you want to sign out of your Storkia account?',
            style: TextStyle(color: StorkTheme.textMain, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: StorkTheme.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: CircularProgressIndicator(color: StorkTheme.primary),
                  ),
                );

                await ref.read(authProvider.notifier).logout();

                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailingBadge,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              StorkTheme.primary.withValues(alpha: 0.14),
              StorkTheme.brandLight.withValues(alpha: 0.38),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: StorkTheme.primaryDark, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: StorkTheme.textMain,
        ),
      ),
      subtitle: subtitle != null
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: StorkTheme.textMuted,
                ),
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingBadge != null) ...[
            trailingBadge,
            const SizedBox(width: 6),
          ],
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: StorkTheme.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.chevron_right_rounded,
              color: StorkTheme.textMuted,
              size: 18,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(children: children),
    );
  }

  Widget _buildOrderQuickShortcut(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tabKey,
    required int badgeCount,
    required String domain,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            StorkRoute.fade(
              OrdersScreen(
                baseUrl: domain,
                token: widget.token,
                initialTab: tabKey,
              ),
            ),
          ).then((_) {
            syncAllBuyerCounters(ref, widget.token);
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: badgeCount > 0
                          ? LinearGradient(
                              colors: [
                                StorkTheme.primary.withValues(alpha: 0.16),
                                StorkTheme.brandLight.withValues(alpha: 0.38),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: badgeCount > 0 ? null : StorkTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: badgeCount > 0
                            ? StorkTheme.primary.withValues(alpha: 0.3)
                            : StorkTheme.borderSubtle,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: badgeCount > 0
                          ? StorkTheme.primary
                          : StorkTheme.primaryDark,
                      size: 21,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -5,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5.5,
                          vertical: 1.5,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        decoration: BoxDecoration(
                          color: StorkTheme.primary,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: StorkTheme.surface,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
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
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight:
                      badgeCount > 0 ? FontWeight.w800 : FontWeight.w700,
                  color: badgeCount > 0
                      ? StorkTheme.primaryDark
                      : StorkTheme.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).user ?? widget.user;
    final rewardState = ref.watch(rewardSummaryProvider);
    final orderCounts = ref.watch(orderCountsProvider);
    final unreadAnnouncements = ref.watch(unreadAnnouncementProvider);
    final domain = ApiConfig.resolveBaseDomain(widget.baseUrl);
    final String avatarUrl = (currentUser.avatarPath != null &&
            currentUser.avatarPath!.trim().isNotEmpty)
        ? ApiConfig.storageUrl(currentUser.avatarPath, domain)
        : '';

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      body: RefreshIndicator(
        color: StorkTheme.primary,
        onRefresh: () async {
          await Future.wait([
            ref.read(authProvider.notifier).refreshUserProfile(),
            syncAllBuyerCounters(ref, widget.token),
          ]);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                decoration: BoxDecoration(
                  gradient: StorkTheme.brandGradient,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: StorkTheme.primaryDark.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              StorkRoute.fade(
                                ProfileScreen(
                                  baseUrl: domain,
                                  token: widget.token,
                                ),
                              ),
                            ).then((_) {
                              ref
                                  .read(authProvider.notifier)
                                  .refreshUserProfile();
                            });
                          },
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 32,
                                  backgroundColor: Colors.white,
                                  backgroundImage: avatarUrl.isNotEmpty
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child: avatarUrl.isEmpty
                                      ? Text(
                                          currentUser.firstName.isNotEmpty
                                              ? currentUser.firstName[0]
                                                  .toUpperCase()
                                              : 'B',
                                          style: const TextStyle(
                                            fontSize: 26,
                                            fontWeight: FontWeight.w900,
                                            color: StorkTheme.primary,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: StorkTheme.primaryDark,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentUser.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (currentUser.username != null &&
                                  currentUser.username!.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(
                                  '@${currentUser.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: StorkTheme.brandLight,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                currentUser.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      currentUser.role.toUpperCase(),
                                      style: const TextStyle(
                                        color: StorkTheme.brandLight,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: currentUser.isIdentityVerified
                                          ? StorkTheme.success
                                              .withValues(alpha: 0.28)
                                          : Colors.black
                                              .withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      currentUser.isIdentityVerified
                                          ? '✓ ID Verified'
                                          : 'ID Unverified',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                StorkRoute.fade(
                                  PointsRewardsScreen(
                                    baseUrl: domain,
                                    token: widget.token,
                                    initialTab: 1,
                                  ),
                                ),
                              ).then((_) {
                                syncAllBuyerCounters(ref, widget.token);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_rounded,
                                        size: 13,
                                        color: StorkTheme.brandLight,
                                      ),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'STORKIA E-WALLET',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: StorkTheme.brandLight,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₱${_formatMoney(rewardState.walletAvailableBalance)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
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
                                  PointsRewardsScreen(
                                    baseUrl: domain,
                                    token: widget.token,
                                    initialTab: 0,
                                  ),
                                ),
                              ).then((_) {
                                syncAllBuyerCounters(ref, widget.token);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.monetization_on_rounded,
                                        size: 13,
                                        color: StorkTheme.brandLight,
                                      ),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'STORKIA COINS',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: StorkTheme.brandLight,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${rewardState.coinsBalance} Coins (₱${_formatMoney(rewardState.coinsPesoEquivalent)})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 14),
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: StorkTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: StorkTheme.borderSubtle),
                    boxShadow: StorkTheme.softCardShadow,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.shopping_bag_outlined,
                                size: 18,
                                color: StorkTheme.primary,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'My Purchases',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              if (orderCounts.all > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: StorkTheme.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${orderCounts.all}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      color: StorkTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                StorkRoute.fade(
                                  OrdersScreen(
                                      baseUrl: domain, token: widget.token),
                                ),
                              ).then((_) {
                                syncAllBuyerCounters(ref, widget.token);
                              });
                            },
                            child: const Text(
                              'View All Orders →',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        children: [
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.pending_actions_rounded,
                            label: 'Unpaid',
                            tabKey: 'unpaid',
                            badgeCount: orderCounts.unpaid,
                            domain: domain,
                          ),
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.inventory_2_outlined,
                            label: 'Processing',
                            tabKey: 'processing',
                            badgeCount: orderCounts.processing,
                            domain: domain,
                          ),
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.local_shipping_outlined,
                            label: 'Shipped',
                            tabKey: 'shipped',
                            badgeCount: orderCounts.shipped,
                            domain: domain,
                          ),
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.mark_chat_read_outlined,
                            label: 'To Confirm',
                            tabKey: 'to_confirm',
                            badgeCount: orderCounts.toConfirm,
                            domain: domain,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.star_outline_rounded,
                            label: 'To Rate',
                            tabKey: 'to_rate',
                            badgeCount: orderCounts.toRate,
                            domain: domain,
                          ),
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.task_alt_rounded,
                            label: 'Completed',
                            tabKey: 'completed',
                            badgeCount: orderCounts.completed,
                            domain: domain,
                          ),
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.assignment_return_outlined,
                            label: 'Returns',
                            tabKey: 'returns',
                            badgeCount: orderCounts.returns,
                            domain: domain,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 14, 22, 4),
                  child: Text(
                    'WALLET, COINS & PROMOTIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: StorkTheme.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                _buildSectionCard(
                  children: [
                    _buildMenuTile(
                      icon: Icons.monetization_on_outlined,
                      title: 'My Points / Coins & E-Wallet',
                      subtitle:
                          'Daily Chest, Spin Wheel, Voucher Redeem & GCash Top-Up',
                      trailingBadge: rewardState.canOpenChest
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: StorkTheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'CHEST READY',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            PointsRewardsScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        ).then((_) {
                          syncAllBuyerCounters(ref, widget.token);
                        });
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.local_offer_outlined,
                      title: 'My Coupons & Voucher Wallet',
                      subtitle:
                          'Claim Platform, Free Shipping & Secret Code Vouchers',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            MyCouponsScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.bolt_rounded,
                      title: 'Super Deals & Flash Promos',
                      subtitle: 'Limited-slot flash deals & store sales',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            SuperDealsScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.redeem_rounded,
                      title: 'Store Bundle Deals',
                      subtitle: 'Multi-item percentage off & free gifts',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            BundleDealsScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 14, 22, 4),
                  child: Text(
                    'SHOPPING ACTIVITY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: StorkTheme.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                _buildSectionCard(
                  children: [
                    _buildMenuTile(
                      icon: Icons.favorite_border_rounded,
                      title: 'Wish List',
                      subtitle: 'Saved items & restock alerts',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            WishlistScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.history_rounded,
                      title: 'Recently Viewed',
                      subtitle: 'Products you recently browsed',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            RecentlyViewedScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.storefront_outlined,
                      title: 'Following Stores',
                      subtitle: 'Stores you follow & ₱30 follower vouchers',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            FollowingStoresScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 14, 22, 4),
                  child: Text(
                    'ACCOUNT SETTINGS & SUPPORT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: StorkTheme.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                _buildSectionCard(
                  children: [
                    _buildMenuTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Public Profile (@Username & Avatar)',
                      subtitle: currentUser.username != null
                          ? '@${currentUser.username}'
                          : 'Set your public @username and profile photo',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            ProfileScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        ).then((_) {
                          ref.read(authProvider.notifier).refreshUserProfile();
                        });
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.manage_accounts_outlined,
                      title: 'Account Management & Security',
                      subtitle: 'Name, Phone, Email OTP, Password & Archive',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            AccountManagementScreen(
                              user: currentUser,
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        ).then((_) {
                          ref.read(authProvider.notifier).refreshUserProfile();
                        });
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.badge_outlined,
                      title: 'Identity Verification (Valid ID)',
                      subtitle: currentUser.isIdentityVerified
                          ? 'Verified ✓'
                          : 'Required for Return & Refund requests',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            IdentityVerificationScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        ).then((_) {
                          ref.read(authProvider.notifier).refreshUserProfile();
                        });
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.location_on_outlined,
                      title: 'Address Book (PSGC)',
                      subtitle: 'Manage standardized delivery addresses',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            AddressSelectionScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.campaign_outlined,
                      title: 'Platform Announcements',
                      trailingBadge: unreadAnnouncements > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: StorkTheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unreadAnnouncements NEW',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            AnnouncementsScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        ).then((_) {
                          syncAllBuyerCounters(ref, widget.token);
                        });
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.flag_outlined,
                      title: 'My Submitted Store Reports',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            SellerReportsScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.support_agent_rounded,
                      title: 'Help Center (Chat with Admin Support)',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            HelpCenterScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 68),
                    _buildMenuTile(
                      icon: Icons.gavel_rounded,
                      title: 'Terms, Privacy & Cookie Policies',
                      subtitle:
                          'Marketplace terms, Data Privacy Act & session rules',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            const LegalPoliciesScreen(initialTab: 0),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StorkTheme.surface,
                      foregroundColor: StorkTheme.danger,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: StorkTheme.danger.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    onPressed: () => _showLogoutDialog(context),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Log Out of Storkia',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
