import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

typedef JsonMap = Map<String, dynamic>;

class MyCouponsScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const MyCouponsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<MyCouponsScreen> createState() => _MyCouponsScreenState();
}

class _MyCouponsScreenState extends State<MyCouponsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final TextEditingController _codeController = TextEditingController();
  Timer? _wsDebounceTimer;

  bool _isLoading = true;
  bool _isClaimingCode = false;
  String? _claimingVoucherCode;

  List<JsonMap> _walletVouchers = [];
  List<JsonMap> _discoverVouchers = [];

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _fetchVouchers(silent: false);
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'voucher' ||
        event.scope == 'wallet' ||
        event.scope == 'order' ||
        event.scope == 'marketplace') {
      _wsDebounceTimer?.cancel();
      _wsDebounceTimer = Timer(const Duration(milliseconds: 260), () {
        if (mounted) {
          _fetchVouchers(silent: true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsDebounceTimer?.cancel();
    WebSocketService.removeListener(_onRealtimeEvent);
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchVouchers(silent: true);
    }
  }

  void _showPopupToast(String message, {bool isError = true}) {
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

  String _formatMoney(dynamic raw) {
    final val = double.tryParse(raw?.toString() ?? '0') ?? 0.0;
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  List<JsonMap> _extractVoucherList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map)
            JsonMap.from(
              item['voucher'] is Map ? (item['voucher'] as Map) : item,
            ),
      ];
    }
    if (raw is Map && raw['data'] is List) {
      return _extractVoucherList(raw['data']);
    }
    return [];
  }

  Future<void> _fetchVouchers({bool silent = true}) async {
    if (!silent && _walletVouchers.isEmpty && _discoverVouchers.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final headers = ApiService.buildHeaders(widget.token);

      final response = await ApiService.httpClient
          .get(Uri.parse('$_domain/api/v1/vouchers'), headers: headers)
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      List<JsonMap> wallet = [];
      List<JsonMap> discover = [];

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final dynamic d = body is Map ? (body['data'] ?? body) : body;
        if (d is Map) {
          wallet = _extractVoucherList(
            d['wallet'] ??
                d['claimed'] ??
                d['my_vouchers'] ??
                d['user_vouchers'],
          );
          discover = _extractVoucherList(
            d['discover'] ??
                d['available'] ??
                d['claimable'] ??
                d['platform_vouchers'] ??
                d['vouchers'],
          );
        } else if (d is List) {
          final all = _extractVoucherList(d);
          wallet = all.where((v) => v['is_claimed'] == true).toList();
          discover = all.where((v) => v['is_claimed'] != true).toList();
        }
      }

      if (discover.isEmpty) {
        try {
          final activeRes = await ApiService.httpClient
              .get(
                Uri.parse('$_domain/api/v1/vouchers/active'),
                headers: headers,
              )
              .timeout(ApiConfig.requestTimeout);
          if (activeRes.statusCode == 200) {
            final activeBody = json.decode(activeRes.body);
            final activeList = _extractVoucherList(
              activeBody is Map
                  ? (activeBody['data'] ?? activeBody)
                  : activeBody,
            );
            final claimedCodes = wallet
                .map((w) => (w['code'] ?? '').toString().toUpperCase())
                .toSet();
            discover = activeList
                .where((v) =>
                    v['is_claimed'] != true &&
                    !claimedCodes
                        .contains((v['code'] ?? '').toString().toUpperCase()))
                .toList();
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _walletVouchers = wallet;
          _discoverVouchers = discover;
          _isLoading = false;
        });
      }
      return;
    } catch (_) {}

    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _claimVoucher(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty || _isClaimingCode || _claimingVoucherCode != null) return;

    setState(() {
      _isClaimingCode = true;
      _claimingVoucherCode = code;
    });

    try {
      final response = await ApiService.httpClient
          .post(
            Uri.parse('$_domain/api/v1/vouchers/claim'),
            headers: ApiService.buildHeaders(widget.token, isJson: true),
            body: json.encode({'code': code}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        _codeController.clear();
        _showPopupToast(
          data['message']?.toString() ??
              'Voucher "$code" added to your wallet!',
          isError: false,
        );
        _fetchVouchers(silent: true);
      } else {
        String errMsg = data is Map
            ? (data['message']?.toString() ?? 'Unable to claim voucher.')
            : 'Unable to claim voucher.';
        if (data is Map &&
            data['errors'] is Map &&
            (data['errors'] as Map).isNotEmpty) {
          final first = (data['errors'] as Map).values.first;
          if (first is List && first.isNotEmpty) {
            errMsg = first.first.toString();
          }
        }
        _showPopupToast(errMsg, isError: true);
      }
    } catch (_) {
      _showPopupToast('Network error occurred.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isClaimingCode = false;
          _claimingVoucherCode = null;
        });
      }
    }
  }

  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _showPopupToast(
      'Voucher code "$code" copied to clipboard!',
      isError: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('My Coupons & Voucher Wallet'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: StorkTheme.primary,
          labelColor: StorkTheme.primary,
          unselectedLabelColor: StorkTheme.textMuted,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
          tabs: [
            Tab(text: 'My Wallet (${_walletVouchers.length})'),
            Tab(text: 'Claim Vouchers (${_discoverVouchers.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: StorkTheme.surface,
              border: Border(
                bottom: BorderSide(color: StorkTheme.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9_-]')),
                      LengthLimitingTextInputFormatter(25),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Enter secret or promo voucher code...',
                      fillColor: StorkTheme.surfaceSubtle,
                      prefixIcon: Icon(
                        Icons.confirmation_number_outlined,
                        size: 19,
                        color: StorkTheme.primary,
                      ),
                    ),
                    onSubmitted: _claimVoucher,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: _isClaimingCode ? null : StorkTheme.brandGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton(
                    onPressed: _isClaimingCode
                        ? null
                        : () => _claimVoucher(_codeController.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isClaimingCode
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Claim Code'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading &&
                    _walletVouchers.isEmpty &&
                    _discoverVouchers.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: StorkTheme.primary),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildVoucherList(
                        items: _walletVouchers,
                        isWallet: true,
                        emptyTitle: 'Your Voucher Wallet Is Empty',
                        emptySubtitle:
                            'Claim Platform or Free Shipping vouchers from the Claim tab, or follow verified stores!',
                      ),
                      _buildVoucherList(
                        items: _discoverVouchers,
                        isWallet: false,
                        emptyTitle: 'No Unclaimed Platform Vouchers Right Now',
                        emptySubtitle:
                            'All available Platform and Free Shipping vouchers are already in your wallet.',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoucherList({
    required List<JsonMap> items,
    required bool isWallet,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    return RefreshIndicator(
      color: StorkTheme.primary,
      onRefresh: () => _fetchVouchers(silent: true),
      child: items.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(32),
              children: [
                const SizedBox(height: 60),
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: StorkTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_activity_outlined,
                      size: 38,
                      color: StorkTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  emptyTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  emptySubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: StorkTheme.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildTicketCard(items[index], isWallet: isWallet);
              },
            ),
    );
  }

  Widget _buildTicketCard(
    JsonMap voucher, {
    required bool isWallet,
  }) {
    final String code = voucher['code']?.toString() ?? 'CODE';
    final String title =
        (voucher['title'] ?? voucher['name'] ?? 'Discount Voucher').toString();
    final String badgeLabel =
        (voucher['badge_label'] ?? 'STORKIA OFF').toString();
    final String scope = (voucher['scope'] ?? 'platform').toString();
    final String description =
        (voucher['description'] ?? 'Valid on qualifying orders.').toString();
    final String minSpend = _formatMoney(voucher['min_spend'] ?? 0);
    final double? maxCap =
        double.tryParse(voucher['max_discount_cap']?.toString() ?? '');
    final String discountType =
        (voucher['discount_type'] ?? 'fixed').toString().toLowerCase();
    final int perBuyerLimit =
        int.tryParse(voucher['per_buyer_limit']?.toString() ?? '1') ?? 1;
    final int timesUsed =
        int.tryParse(voucher['times_used']?.toString() ?? '0') ?? 0;
    final String expiresAt =
        (voucher['ends_at_formatted'] ?? voucher['expires_at'] ?? 'Active')
            .toString();
    final bool isUsable = voucher['is_usable'] != false;
    final String? storeName = voucher['seller_name']?.toString() ??
        (voucher['seller_profile'] is Map
            ? voucher['seller_profile']['business_name']?.toString()
            : null);

    final Color accentColor = scope == 'shipping'
        ? const Color(0xFF047857)
        : (scope == 'store' ? StorkTheme.primary : const Color(0xFF6B21A8));

    return Opacity(
      opacity: (isWallet && !isUsable) ? 0.55 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: StorkTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: StorkTheme.borderSubtle),
          boxShadow: StorkTheme.softCardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 104,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor,
                      accentColor.withValues(alpha: 0.82),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        scope.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      badgeLabel,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    if (discountType == 'percentage' &&
                        maxCap != null &&
                        maxCap > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Cap ₱${maxCap.toStringAsFixed(0)}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Min ₱$minSpend',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  StorkTheme.brandLight.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              code,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: StorkTheme.primaryDark,
                              ),
                            ),
                          ),
                          if (storeName != null && storeName.isNotEmpty)
                            Text(
                              storeName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                          if (isWallet && perBuyerLimit > 0)
                            Text(
                              '• Used $timesUsed/$perBuyerLimit',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
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
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'Valid until: $expiresAt',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: StorkTheme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isWallet)
                            ElevatedButton(
                              onPressed: isUsable
                                  ? () => _copyToClipboard(code)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                minimumSize: const Size(0, 30),
                              ),
                              child: Text(
                                isUsable ? 'Copy Code' : 'Used / Expired',
                                style: const TextStyle(fontSize: 11),
                              ),
                            )
                          else
                            ElevatedButton(
                              onPressed: _claimingVoucherCode == code
                                  ? null
                                  : () => _claimVoucher(code),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                minimumSize: const Size(0, 30),
                              ),
                              child: _claimingVoucherCode == code
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Claim',
                                      style: TextStyle(fontSize: 11),
                                    ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
