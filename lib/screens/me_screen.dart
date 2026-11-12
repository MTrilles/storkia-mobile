import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/global_counters_provider.dart';
import 'account_management_screen.dart';
import 'address_selection_screen.dart';
import 'announcements_screen.dart';
import 'bundle_deals_screen.dart';
import 'following_stores_screen.dart';
import 'help_center_screen.dart';
import 'identity_verification_screen.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).refreshUserProfile();
      syncAllBuyerCounters(ref, widget.token);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: StorkTheme.brandLight.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: StorkTheme.primary, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: StorkTheme.textMain,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: StorkTheme.textMuted,
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
          const Icon(
            Icons.chevron_right_rounded,
            color: StorkTheme.textMuted,
            size: 20,
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildOrderQuickShortcut(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tabKey,
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
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, color: StorkTheme.primaryDark, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: StorkTheme.textMain,
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
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [StorkTheme.primaryDark, StorkTheme.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
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
                          child: CircleAvatar(
                            radius: 32,
                            backgroundColor: Colors.white,
                            backgroundImage: avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    currentUser.firstName.isNotEmpty
                                        ? currentUser.firstName[0].toUpperCase()
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
                                      currentUser.role,
                                      style: const TextStyle(
                                        color: StorkTheme.brandLight,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: currentUser.isIdentityVerified
                                          ? StorkTheme.success
                                              .withValues(alpha: 0.25)
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
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'STORKIA E-WALLET',
                                    style: TextStyle(
                                      color: StorkTheme.brandLight,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
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
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'STORKIA COINS',
                                    style: TextStyle(
                                      color: StorkTheme.brandLight,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
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
                const SizedBox(height: 12),
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: StorkTheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: StorkTheme.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'My Purchases',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                StorkRoute.fade(
                                  OrdersScreen(
                                      baseUrl: domain, token: widget.token),
                                ),
                              );
                            },
                            child: const Text(
                              'View All Orders →',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: StorkTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 18),
                      Row(
                        children: [
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.inventory_2_outlined,
                            label: 'Processing',
                            tabKey: 'processing',
                            domain: domain,
                          ),
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.local_shipping_outlined,
                            label: 'Shipped',
                            tabKey: 'shipped',
                            domain: domain,
                          ),
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.mark_chat_read_outlined,
                            label: 'To Confirm',
                            tabKey: 'to_confirm',
                            domain: domain,
                          ),
                          _buildOrderQuickShortcut(
                            context,
                            icon: Icons.star_outline_rounded,
                            label: 'To Rate',
                            tabKey: 'to_rate',
                            domain: domain,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 12, 22, 4),
                  child: Text(
                    'WALLET, COINS & PROMOTIONS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
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
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 60),
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
                    const Divider(height: 1, indent: 60),
                    _buildMenuTile(
                      icon: Icons.bolt_rounded,
                      title: 'Super Deals & Bundle Promos',
                      subtitle: 'Flash slots & Buy X Get Y Free Gift bundles',
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
                    const Divider(height: 1, indent: 60),
                    _buildMenuTile(
                      icon: Icons.redeem_rounded,
                      title: 'Store Bundle Deals',
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
                  padding: EdgeInsets.fromLTRB(22, 12, 22, 4),
                  child: Text(
                    'SHOPPING ACTIVITY',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
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
                    const Divider(height: 1, indent: 60),
                    _buildMenuTile(
                      icon: Icons.history_rounded,
                      title: 'Recently Viewed',
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
                    const Divider(height: 1, indent: 60),
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
                  padding: EdgeInsets.fromLTRB(22, 12, 22, 4),
                  child: Text(
                    'ACCOUNT SETTINGS & SUPPORT',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
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
                    const Divider(height: 1, indent: 60),
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
                    const Divider(height: 1, indent: 60),
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
                    const Divider(height: 1, indent: 60),
                    _buildMenuTile(
                      icon: Icons.location_on_outlined,
                      title: 'Address Book (PSGC)',
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
                    const Divider(height: 1, indent: 60),
                    _buildMenuTile(
                      icon: Icons.campaign_outlined,
                      title: 'Platform Announcements',
                      onTap: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            AnnouncementsScreen(
                              baseUrl: domain,
                              token: widget.token,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 60),
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
                    const Divider(height: 1, indent: 60),
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
                  ],
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StorkTheme.surface,
                      foregroundColor: StorkTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: StorkTheme.primary.withValues(alpha: 0.35),
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
                          'Log Out',
                          style: TextStyle(
                            fontSize: 15,
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
