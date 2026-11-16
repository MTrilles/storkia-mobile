import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';

class LegalPoliciesScreen extends StatefulWidget {
  final int initialTab;

  const LegalPoliciesScreen({
    super.key,
    this.initialTab = 0,
  });

  @override
  State<LegalPoliciesScreen> createState() => _LegalPoliciesScreenState();
}

class _LegalPoliciesScreenState extends State<LegalPoliciesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _expandedSections = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Legal & Platform Policies'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: StorkTheme.primary,
          labelColor: StorkTheme.primary,
          unselectedLabelColor: StorkTheme.textMuted,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
          tabs: const [
            Tab(text: 'Terms & Conditions'),
            Tab(text: 'Privacy Policy'),
            Tab(text: 'Cookie & Session Policy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTermsTab(),
          _buildPrivacyTab(),
          _buildCookieTab(),
        ],
      ),
    );
  }

  Widget _buildHeaderBanner({
    required IconData icon,
    required String badge,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: StorkTheme.brandGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: StorkTheme.primaryDark.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge,
                  style: const TextStyle(
                    color: StorkTheme.brandLight,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                    height: 1.38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicySection({
    required String sectionKey,
    required String number,
    required String title,
    required List<String> paragraphs,
  }) {
    final bool isExpanded = _expandedSections.contains(sectionKey);
    final bool hasMultipleOrLong = paragraphs.length > 1 ||
        (paragraphs.isNotEmpty && paragraphs.first.length > 150);
    final List<String> visibleParagraphs =
        (hasMultipleOrLong && !isExpanded) ? [paragraphs.first] : paragraphs;

    return Container(
      margin: const EdgeInsets.only(top: 12),
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
          InkWell(
            onTap: hasMultipleOrLong
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (isExpanded) {
                        _expandedSections.remove(sectionKey);
                      } else {
                        _expandedSections.add(sectionKey);
                      }
                    });
                  }
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: StorkTheme.brandGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    number,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < visibleParagraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Text(
              visibleParagraphs[i],
              maxLines: (hasMultipleOrLong && !isExpanded) ? 3 : 50,
              overflow: (hasMultipleOrLong && !isExpanded)
                  ? TextOverflow.ellipsis
                  : TextOverflow.visible,
              style: const TextStyle(
                fontSize: 12.5,
                color: StorkTheme.textMain,
                height: 1.5,
              ),
            ),
          ],
          if (hasMultipleOrLong) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (isExpanded) {
                    _expandedSections.remove(sectionKey);
                  } else {
                    _expandedSections.add(sectionKey);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isExpanded ? 'See Less' : 'See More',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: StorkTheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTermsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderBanner(
          icon: Icons.gavel_rounded,
          badge: 'STORKIA MARKETPLACE TERMS',
          title: 'Terms & Conditions of Use',
          subtitle:
              'Governing buyer accounts, checkout protection, E-Wallet escrow, Storkia Coins, and returns across Storkia Web & Mobile.',
        ),
        _buildPolicySection(
          sectionKey: 'terms_01',
          number: '01',
          title: 'Account Eligibility & Security',
          paragraphs: const [
            'Buyers must be at least 18 years old and register with a verified email address via 6-digit One-Time Password (OTP) authentication.',
            'Your Philippine mobile number (+63 9XXXXXXXXX / 09XXXXXXXXX) and PSGC delivery address must be accurate to ensure successful first-mile and last-mile parcel delivery.',
          ],
        ),
        _buildPolicySection(
          sectionKey: 'terms_02',
          number: '02',
          title: 'Orders, 24-Hour Seller SLA & Cancellation Quota',
          paragraphs: const [
            'Every placed order is grouped by merchant into individual Seller Orders. Sellers have 24 hours to accept incoming orders. If a seller fails to respond within 24 hours, the order is automatically cancelled, any Storkia E-Wallet payment is immediately refunded, and you receive +50 Storkia Coins as compensation.',
            'Buyers may cancel an order before the package is marked Ready for Pickup, subject to Anti-Sabotage Cancellation Protection limits (up to 5 cancellations per 7-day rolling window).',
          ],
        ),
        _buildPolicySection(
          sectionKey: 'terms_03',
          number: '03',
          title: 'Payment Methods, Storkia E-Wallet & COD Rules',
          paragraphs: const [
            'Storkia supports Cash on Delivery (COD) and Real-Money Storkia E-Wallet payments. E-Wallet balances are topped up via GCash receipt screenshot verification by Storkia Admin Escrow.',
            'Repeatedly abandoning or refusing valid COD parcels at doorstep delivery results in COD Abandonment Strikes. Reaching 3 strikes triggers a 7-day temporary suspension and requires an appeal.',
          ],
        ),
        _buildPolicySection(
          sectionKey: 'terms_04',
          number: '04',
          title: '72-Hour Buyer Protection & Return / Refund Policy',
          paragraphs: const [
            'Once a parcel is marked Delivered with photo proof, you have 72 hours (3 days) to inspect the item and either confirm receipt or submit a Return & Refund request.',
            'To prevent marketplace fraud, submitting a Return & Refund request requires an approved Valid Government ID under Identity Verification, 1 to 5 clear evidence photos, and a detailed explanation.',
            'Approved refunds can be credited immediately to your Storkia E-Wallet or disbursed to your verified GCash account. If a seller rejects your request, you may escalate the case to Storkia Admin for final arbitration.',
          ],
        ),
        _buildPolicySection(
          sectionKey: 'terms_05',
          number: '05',
          title: 'Storkia Coins, Vouchers & Promotions',
          paragraphs: const [
            'Storkia Coins earned from Daily Treasure Chests, 24-Hour Spin Wheels, Order Completion Cashback, and Verified Product Reviews can be redeemed at checkout at the rate of 10 Coins = ₱1.00 (minimum 10 coins, up to 25% of net merchandise subtotal) or exchanged for platform and shipping vouchers.',
            'At checkout, Storkia automatically recommends the Most Preferred eligible Store, Platform, and Free Shipping vouchers to maximize your savings.',
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPrivacyTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderBanner(
          icon: Icons.privacy_tip_outlined,
          badge: 'REPUBLIC ACT NO. 10173 COMPLIANCE',
          title: 'Storkia Privacy Policy',
          subtitle:
              'How we collect, protect, and process your personal data in compliance with the Philippine Data Privacy Act of 2012.',
        ),
        _buildPolicySection(
          sectionKey: 'privacy_01',
          number: '01',
          title: 'Information We Collect',
          paragraphs: const [
            'Account & Profile Data: Legal name, @username, birthday, sex, email address, and Philippine mobile number (+63 / 09 format).',
            'Delivery & Fulfillment Data: PSGC-standardized province, city/municipality, barangay, street address, and delivery chat messages with assigned riders.',
            'Verification & Financial Proofs: Government ID images submitted for Identity Verification and GCash transfer screenshots submitted for E-Wallet top-ups.',
          ],
        ),
        _buildPolicySection(
          sectionKey: 'privacy_02',
          number: '02',
          title: 'How Your Data Is Used',
          paragraphs: const [
            'We use your personal information strictly to process orders, calculate distance-tiered shipping fees, route parcels through partner logistics sorting hubs, verify E-Wallet top-ups, and resolve return or refund disputes.',
            'Merchants and logistics riders only see the recipient name, delivery address, and contact number necessary to fulfill and deliver your active order.',
          ],
        ),
        _buildPolicySection(
          sectionKey: 'privacy_03',
          number: '03',
          title: 'Document Security & Account Archiving',
          paragraphs: const [
            'Government ID uploads and delivery proof photos are stored in access-controlled storage and are only viewable by authorized Storkia Compliance Administrators and the account owner.',
            'You may archive/deactivate your account at any time under Account Management once all in-progress orders and open disputes are settled.',
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCookieTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderBanner(
          icon: Icons.security_rounded,
          badge: 'SESSION & STORAGE TRANSPARENCY',
          title: 'Cookie & Mobile Session Policy',
          subtitle:
              'How Storkia Web and Mobile use authentication tokens, local preferences, and real-time synchronization.',
        ),
        _buildPolicySection(
          sectionKey: 'cookie_01',
          number: '01',
          title: 'Sanctum API Tokens & Session Security',
          paragraphs: const [
            'The Storkia Mobile App uses encrypted Laravel Sanctum Bearer tokens stored locally on your device to keep you signed in securely without requiring repeated logins.',
            'When you change your password, archive your account, or sign out, active tokens are revoked immediately.',
          ],
        ),
        _buildPolicySection(
          sectionKey: 'cookie_02',
          number: '02',
          title: 'Local Device Storage',
          paragraphs: const [
            'We store lightweight local data on your device solely for essential shopping features, including your Recently Viewed products list, active authentication session, and real-time cart/notification counters.',
            'Storkia does not sell or share your browsing behavior with third-party advertising networks.',
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
