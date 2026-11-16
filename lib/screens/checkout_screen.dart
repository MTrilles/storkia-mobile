import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/address_model.dart';
import '../providers/global_counters_provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'address_selection_screen.dart';
import 'checkout_success_screen.dart';
import 'points_rewards_screen.dart';

typedef JsonMap = Map<String, dynamic>;
typedef IntStringMap = Map<int, String>;
typedef IntControllerMap = Map<int, TextEditingController>;
typedef StringMap = Map<String, String>;

class CheckoutScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;
  final String mode;
  final List<int>? cartIds;
  final JsonMap? buyNowData;

  const CheckoutScreen({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.mode,
    this.cartIds,
    this.buyNowData,
  });

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isSyncingPreview = false;
  bool _isSubmitting = false;
  int _previewRequestSeq = 0;
  Timer? _wsDebounceTimer;
  String? _lastErrorMessage;
  String _lastShownNoticeSignature = '';

  JsonMap? _checkoutData;
  Address? _selectedAddress;
  bool _isAddressServiceable = true;
  String? _idempotencyKey;
  String? _priceSignature;

  bool _isAddressExpanded = false;
  final Set<int> _expandedPackageItems = <int>{};
  final Set<int> _expandedPackageBreakdowns = <int>{};
  bool _isVouchersSectionExpanded = false;
  bool _isOrderSummaryExpanded = false;

  double _buyerWalletBalance = 0.0;
  int _buyerCoinsBalance = 0;
  int _maxRedeemableCoins = 0;
  int _minRedeemableCoins = 10;
  bool _useStorkiaCoins = false;
  int _coinsToUse = 0;
  final TextEditingController _coinsInputController = TextEditingController();

  final IntStringMap _paymentMethods = {};
  final IntControllerMap _noteControllers = {};
  final IntControllerMap _storeVoucherControllers = {};
  final IntStringMap _appliedStoreVouchers = {};

  final Set<String> _touchedSlots = <String>{};
  final IntStringMap _recommendedStoreVouchers = {};
  String _recommendedPlatformVoucher = '';
  String _recommendedShippingVoucher = '';

  final TextEditingController _platformVoucherController =
      TextEditingController();
  final TextEditingController _shippingVoucherController =
      TextEditingController();
  String _appliedPlatformVoucherCode = '';
  String _appliedShippingVoucherCode = '';

  List<JsonMap> _availableVouchers = [];

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchPreview(silent: false);
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'cart' ||
        event.scope == 'wallet' ||
        event.scope == 'catalog' ||
        event.scope == 'marketplace' ||
        event.scope == 'order') {
      _wsDebounceTimer?.cancel();
      _wsDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && !_isSubmitting && !_isLoading && !_isSyncingPreview) {
          _fetchPreview(silent: true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsDebounceTimer?.cancel();
    WebSocketService.removeListener(_onRealtimeEvent);
    for (final ctrl in _noteControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _storeVoucherControllers.values) {
      ctrl.dispose();
    }
    _coinsInputController.dispose();
    _platformVoucherController.dispose();
    _shippingVoucherController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isSubmitting) {
      _fetchPreview(silent: true);
    }
  }

  Widget _buildSeeMoreToggle({
    required bool isExpanded,
    required String moreLabel,
    String lessLabel = 'See Less',
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isExpanded ? lessLabel : moreLabel,
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
    );
  }

  Future<void> _copyTextWithToast(String text, String label) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: cleaned));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    _showPopupNotification(
      'Copied $label: $cleaned',
      isError: false,
    );
  }

  void _showPopupNotification(
    String message, {
    bool isError = true,
    bool isWarning = false,
  }) {
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
                  : (isWarning
                      ? Icons.info_outline_rounded
                      : Icons.check_circle_outline_rounded),
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
        backgroundColor: isError
            ? StorkTheme.danger
            : (isWarning ? const Color(0xFFB45309) : StorkTheme.success),
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

  List<dynamic> _extractList(dynamic value) {
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[];
  }

  double _computeVoucherDiscount(JsonMap? voucher, double baseAmount) {
    if (voucher == null || baseAmount <= 0) return 0.0;
    final double minSpend =
        double.tryParse(voucher['min_spend']?.toString() ?? '0') ?? 0.0;
    if (baseAmount + 0.0001 < minSpend) return 0.0;
    final String type =
        (voucher['discount_type'] ?? 'fixed').toString().toLowerCase();
    final double val =
        double.tryParse(voucher['discount_value']?.toString() ?? '0') ?? 0.0;
    final double? maxCap =
        double.tryParse(voucher['max_discount_cap']?.toString() ?? '');
    double disc = 0.0;
    if (type == 'percentage') {
      disc = baseAmount * (val / 100.0);
      if (maxCap != null && maxCap > 0 && disc > maxCap) {
        disc = maxCap;
      }
    } else {
      disc = val;
    }
    if (disc > baseAmount) disc = baseAmount;
    return double.parse(disc.toStringAsFixed(2));
  }

  JsonMap? _findAvailableVoucher(String code, {String? scope, int? sellerId}) {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) return null;
    for (final v in _availableVouchers) {
      final vCode = (v['code'] ?? '').toString().trim().toUpperCase();
      if (vCode != clean) continue;
      if (scope != null && v['scope']?.toString() != scope) continue;
      if (sellerId != null &&
          int.tryParse(v['seller_profile_id']?.toString() ?? '0') != sellerId) {
        continue;
      }
      return v;
    }
    return null;
  }

  double _resolveNetAfterStoreDiscounts() {
    if (_checkoutData == null) return 0.0;
    final List<dynamic> rawPackages =
        _extractList(_checkoutData!['seller_packages']);
    final double overallSub = double.tryParse(
            _checkoutData!['overall_subtotal']?.toString() ?? '0') ??
        0.0;
    double totalStoreAndBundleDisc = 0.0;
    for (final rawPkg in rawPackages) {
      if (rawPkg is! Map) continue;
      final sellerMap = rawPkg['seller_profile'] is Map
          ? JsonMap.from(rawPkg['seller_profile'] as Map)
          : <String, dynamic>{};
      final int spId = int.tryParse(sellerMap['id']?.toString() ?? '0') ?? 0;
      final double pkgSub =
          double.tryParse(rawPkg['subtotal']?.toString() ?? '0') ?? 0.0;
      final double bundleDisc =
          double.tryParse(rawPkg['bundle_discount']?.toString() ?? '0') ?? 0.0;
      final String storeCode = _appliedStoreVouchers[spId] ?? '';
      final storeVoucher =
          _findAvailableVoucher(storeCode, scope: 'store', sellerId: spId);
      final double storeDisc = _computeVoucherDiscount(
          storeVoucher, (pkgSub - bundleDisc).clamp(0.0, double.infinity));
      totalStoreAndBundleDisc += (bundleDisc + storeDisc);
    }
    return (overallSub - totalStoreAndBundleDisc).clamp(0.0, double.infinity);
  }

  void _applyOptimisticLocalCalculation() {
    if (_checkoutData == null) return;
    final List<dynamic> rawPackages =
        _extractList(_checkoutData!['seller_packages']);
    final double overallSub = double.tryParse(
            _checkoutData!['overall_subtotal']?.toString() ?? '0') ??
        0.0;
    final double overallShip = double.tryParse(
            _checkoutData!['overall_shipping']?.toString() ?? '0') ??
        0.0;
    double totalStoreAndBundleDisc = 0.0;
    for (final rawPkg in rawPackages) {
      if (rawPkg is! Map) continue;
      final sellerMap = rawPkg['seller_profile'] is Map
          ? JsonMap.from(rawPkg['seller_profile'] as Map)
          : <String, dynamic>{};
      final int spId = int.tryParse(sellerMap['id']?.toString() ?? '0') ?? 0;
      final double pkgSub =
          double.tryParse(rawPkg['subtotal']?.toString() ?? '0') ?? 0.0;
      final double bundleDisc =
          double.tryParse(rawPkg['bundle_discount']?.toString() ?? '0') ?? 0.0;
      final String storeCode = _appliedStoreVouchers[spId] ?? '';
      final storeVoucher =
          _findAvailableVoucher(storeCode, scope: 'store', sellerId: spId);
      final double storeDisc = _computeVoucherDiscount(
          storeVoucher, (pkgSub - bundleDisc).clamp(0.0, double.infinity));
      totalStoreAndBundleDisc += (bundleDisc + storeDisc);
    }
    final double netAfterStore =
        (overallSub - totalStoreAndBundleDisc).clamp(0.0, double.infinity);
    final platVoucher =
        _findAvailableVoucher(_appliedPlatformVoucherCode, scope: 'platform');
    final double platDisc = _computeVoucherDiscount(platVoucher, netAfterStore);
    final shipVoucher =
        _findAvailableVoucher(_appliedShippingVoucherCode, scope: 'shipping');
    final double shipDisc = _computeVoucherDiscount(shipVoucher, overallShip);
    final int activeCoins =
        (_useStorkiaCoins && _maxRedeemableCoins >= _minRedeemableCoins)
            ? _coinsToUse.clamp(0, _maxRedeemableCoins)
            : 0;
    final double coinsDisc =
        double.parse((activeCoins * 0.10).toStringAsFixed(2));
    final double newOverallTotal =
        ((overallSub - totalStoreAndBundleDisc - platDisc - coinsDisc)
                .clamp(0.0, double.infinity)) +
            ((overallShip - shipDisc).clamp(0.0, double.infinity));
    setState(() {
      _checkoutData!['overall_store_discount'] = totalStoreAndBundleDisc;
      _checkoutData!['overall_platform_discount'] = platDisc;
      _checkoutData!['overall_shipping_discount'] = shipDisc;
      _checkoutData!['overall_coins_used'] = activeCoins;
      _checkoutData!['overall_coins_discount'] = coinsDisc;
      _checkoutData!['overall_total'] =
          double.parse(newOverallTotal.toStringAsFixed(2));
    });
  }

  Future<Address?> _resolveDefaultAddressSilently() async {
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('$_domain/api/v1/addresses'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final dynamic raw = body is Map ? (body['data'] ?? body) : body;
        List<dynamic> list = [];
        if (raw is List) {
          list = raw;
        } else if (raw is Map && raw['addresses'] is List) {
          list = raw['addresses'] as List<dynamic>;
        }
        final List<Address> parsed = [
          for (final item in list)
            if (item is Map) Address.fromJson(JsonMap.from(item)),
        ];
        if (parsed.isNotEmpty) {
          return parsed.firstWhere(
            (a) => a.isDefault,
            orElse: () => parsed.first,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchPreview({int? addressId, bool silent = true}) async {
    final int reqId = ++_previewRequestSeq;
    final bool showFullLoader = !silent && _checkoutData == null;
    if (showFullLoader) {
      setState(() {
        _isLoading = true;
        _lastErrorMessage = null;
      });
    } else if (mounted) {
      setState(() => _isSyncingPreview = true);
    }
    try {
      int? targetAddressId = addressId ?? _selectedAddress?.id;
      if (targetAddressId == null) {
        final preResolved = await _resolveDefaultAddressSilently();
        if (preResolved != null) {
          _selectedAddress ??= preResolved;
          targetAddressId = preResolved.id;
        }
      }
      final JsonMap payload = {
        'mode': widget.mode,
        'use_storkia_coins': _useStorkiaCoins,
        'touched_slots': _touchedSlots.toList(),
      };
      if (_useStorkiaCoins && _coinsToUse > 0) {
        payload['coins_to_use'] = _coinsToUse;
      }
      if (targetAddressId != null) {
        payload['address_id'] = targetAddressId;
        payload['user_address_id'] = targetAddressId;
      }
      if (widget.mode == 'cart' && widget.cartIds != null) {
        payload['cart_ids'] = widget.cartIds;
      } else if (widget.mode == 'buy_now' && widget.buyNowData != null) {
        payload.addAll(widget.buyNowData!);
      }
      final StringMap storeCodes = {};
      _appliedStoreVouchers.forEach((spId, code) {
        if (code.trim().isNotEmpty) {
          storeCodes[spId.toString()] = code.trim().toUpperCase();
        }
      });
      if (storeCodes.isNotEmpty) {
        payload['store_vouchers'] = storeCodes;
        payload['store_voucher_codes'] = storeCodes;
      }
      if (_appliedPlatformVoucherCode.trim().isNotEmpty) {
        payload['platform_voucher_code'] =
            _appliedPlatformVoucherCode.trim().toUpperCase();
      }
      if (_appliedShippingVoucherCode.trim().isNotEmpty) {
        payload['shipping_voucher_code'] =
            _appliedShippingVoucherCode.trim().toUpperCase();
      }
      final response = await ApiService.httpClient
          .post(
            Uri.parse('$_domain/api/v1/checkout/preview'),
            headers: ApiService.buildHeaders(widget.token, isJson: true),
            body: json.encode(payload),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted || reqId != _previewRequestSeq) return;
      final body = json.decode(response.body);
      final JsonMap? resolvedDataMap = (body is Map && body['data'] is Map)
          ? JsonMap.from(body['data'] as Map)
          : (body is Map && body['seller_packages'] is List
              ? JsonMap.from(body)
              : null);

      if (response.statusCode == 200 && resolvedDataMap != null) {
        final data = resolvedDataMap;
        final List<dynamic> rawPackages = _extractList(data['seller_packages']);
        final List<dynamic> rawAvailableVouchers =
            _extractList(data['available_vouchers']);
        final List<dynamic> rawNotices = _extractList(data['voucher_notices']);
        final List<String> parsedNotices = [
          for (final e in rawNotices)
            if (e != null && e.toString().trim().isNotEmpty)
              e.toString().trim(),
        ];

        setState(() {
          _checkoutData = data;
          _lastErrorMessage = null;
          _idempotencyKey ??= data['idempotency_key']?.toString();
          _priceSignature = data['price_signature']?.toString();
          _isAddressServiceable = data['is_address_serviceable'] != false;
          _buyerWalletBalance = double.tryParse(
                  data['buyer_wallet_balance']?.toString() ?? '0') ??
              0.0;
          _buyerCoinsBalance =
              int.tryParse(data['buyer_coins_balance']?.toString() ?? '0') ?? 0;
          _maxRedeemableCoins =
              int.tryParse(data['max_redeemable_coins']?.toString() ?? '0') ??
                  0;
          _minRedeemableCoins =
              int.tryParse(data['min_redeemable_coins']?.toString() ?? '10') ??
                  10;

          final int serverCoinsUsed =
              int.tryParse(data['overall_coins_used']?.toString() ?? '0') ?? 0;
          if (_maxRedeemableCoins < _minRedeemableCoins) {
            _useStorkiaCoins = false;
            _coinsToUse = 0;
            _coinsInputController.text = '0';
          } else if (_useStorkiaCoins) {
            _coinsToUse =
                serverCoinsUsed > 0 ? serverCoinsUsed : _maxRedeemableCoins;
            _coinsInputController.text = '$_coinsToUse';
          }

          if (data['selected_address'] is Map) {
            _selectedAddress = Address.fromJson(
              JsonMap.from(data['selected_address'] as Map),
            );
          }

          if (data['recommended_vouchers'] is Map) {
            final rec = JsonMap.from(data['recommended_vouchers'] as Map);
            _recommendedStoreVouchers.clear();
            if (rec['store'] is Map) {
              (rec['store'] as Map).forEach((k, v) {
                final id = int.tryParse(k.toString()) ?? 0;
                if (id > 0 && v != null) {
                  _recommendedStoreVouchers[id] = v.toString().toUpperCase();
                }
              });
            }
            _recommendedPlatformVoucher =
                (rec['platform']?.toString() ?? '').toUpperCase();
            _recommendedShippingVoucher =
                (rec['shipping']?.toString() ?? '').toUpperCase();
          }

          _availableVouchers = [
            for (final v in rawAvailableVouchers)
              if (v is Map) JsonMap.from(v),
          ];

          final appliedPlat = data['applied_platform_voucher'];
          _appliedPlatformVoucherCode =
              appliedPlat is Map ? (appliedPlat['code']?.toString() ?? '') : '';
          _platformVoucherController.text = _appliedPlatformVoucherCode;

          final appliedShip = data['applied_shipping_voucher'];
          _appliedShippingVoucherCode =
              appliedShip is Map ? (appliedShip['code']?.toString() ?? '') : '';
          _shippingVoucherController.text = _appliedShippingVoucherCode;

          for (final rawPkg in rawPackages) {
            if (rawPkg is! Map) continue;
            final pkg = JsonMap.from(rawPkg);
            final sellerProfile = pkg['seller_profile'] is Map
                ? JsonMap.from(pkg['seller_profile'] as Map)
                : <String, dynamic>{};
            final int spId =
                int.tryParse(sellerProfile['id']?.toString() ?? '0') ?? 0;
            if (spId <= 0) continue;

            if (!_paymentMethods.containsKey(spId)) {
              _paymentMethods[spId] = 'COD';
            }
            _noteControllers.putIfAbsent(spId, () => TextEditingController());
            _storeVoucherControllers.putIfAbsent(
                spId, () => TextEditingController());

            final storeVoucher = pkg['store_voucher'];
            final appliedStoreCode = storeVoucher is Map
                ? (storeVoucher['code']?.toString() ?? '')
                : '';
            _appliedStoreVouchers[spId] = appliedStoreCode;
            _storeVoucherControllers[spId]!.text = appliedStoreCode;
          }

          _isLoading = false;
          _isSyncingPreview = false;
        });

        if (parsedNotices.isNotEmpty) {
          final joinedNotices = parsedNotices.join(' ');
          if (joinedNotices != _lastShownNoticeSignature) {
            _lastShownNoticeSignature = joinedNotices;
            _showPopupNotification(
              parsedNotices.first,
              isError: false,
              isWarning: true,
            );
          }
        } else {
          _lastShownNoticeSignature = '';
        }
      } else {
        String msg = body is Map
            ? (body['message']?.toString() ??
                'Failed to load checkout preview.')
            : 'Failed to load checkout preview.';
        if (body is Map &&
            body['errors'] is Map &&
            (body['errors'] as Map).isNotEmpty) {
          final firstVal = (body['errors'] as Map).values.first;
          if (firstVal is List && firstVal.isNotEmpty) {
            msg = firstVal.first.toString();
          }
        }
        if (_checkoutData == null) {
          _lastErrorMessage = msg;
        }
        _showError(msg);
      }
    } catch (_) {
      if (!silent) {
        if (_checkoutData == null) {
          _lastErrorMessage = 'Network error occurred while loading checkout.';
        }
        _showError('Network error occurred while loading checkout.');
      }
    } finally {
      if (mounted && reqId == _previewRequestSeq) {
        setState(() {
          _isLoading = false;
          _isSyncingPreview = false;
        });
      }
    }
  }

  double get _totalWalletRequired {
    if (_checkoutData == null) return 0.0;
    double sum = 0.0;
    final List<dynamic> packages =
        _extractList(_checkoutData!['seller_packages']);
    for (final rawPkg in packages) {
      if (rawPkg is! Map) continue;
      final sellerMap = rawPkg['seller_profile'] is Map
          ? JsonMap.from(rawPkg['seller_profile'] as Map)
          : <String, dynamic>{};
      final int spId = int.tryParse(sellerMap['id']?.toString() ?? '0') ?? 0;
      if ((_paymentMethods[spId] ?? 'COD') == 'WALLET') {
        sum += double.tryParse(rawPkg['total']?.toString() ?? '0') ?? 0.0;
      }
    }
    return sum;
  }

  bool get _hasSufficientWalletBalance =>
      (_buyerWalletBalance + 0.0001) >= _totalWalletRequired;

  String? get _firstPackageUnserviceableReason {
    if (_checkoutData == null) return null;
    final List<dynamic> packages =
        _extractList(_checkoutData!['seller_packages']);
    for (final rawPkg in packages) {
      if (rawPkg is! Map) continue;
      final shipping = rawPkg['shipping'];
      if (shipping is Map && shipping['is_serviceable'] == false) {
        final reason = shipping['unserviceable_reason']?.toString().trim();
        if (reason != null && reason.isNotEmpty) {
          return reason;
        }
        return 'No single Storkia Logistics Partner currently connects the seller\'s Origin Hub with an active Destination Branch Hub and local Barangay Rider in your municipality.';
      }
    }
    return null;
  }

  List<String> get _checkoutBlockers {
    final List<String> reasons = [];
    if (_selectedAddress == null) {
      reasons.add('Select or add a delivery address.');
    } else if (!_isAddressServiceable ||
        _firstPackageUnserviceableReason != null) {
      reasons.add(
        _firstPackageUnserviceableReason ??
            'Your selected delivery address is outside our active Last-Mile Logistics Hub & Barangay Rider coverage zones. Please select another address.',
      );
    }
    if (!_hasSufficientWalletBalance) {
      final shortfall = _totalWalletRequired - _buyerWalletBalance;
      reasons.add(
        'Insufficient Storkia E-Wallet balance (Need \u20B1${_formatMoney(shortfall)} more). Top up via GCash or switch to Cash on Delivery (COD).',
      );
    }
    return reasons;
  }

  void _handlePlaceOrderTap() {
    if (_isSubmitting) return;
    final blockers = _checkoutBlockers;
    if (blockers.isNotEmpty) {
      _showError(blockers.first);
      return;
    }
    _placeOrder();
  }

  Future<void> _placeOrder() async {
    final blockers = _checkoutBlockers;
    if (blockers.isNotEmpty) {
      _showError(blockers.first);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);

    try {
      final StringMap notesMap = {};
      _noteControllers.forEach((spId, ctrl) {
        if (ctrl.text.trim().isNotEmpty) {
          notesMap[spId.toString()] = ctrl.text.trim();
        }
      });

      final StringMap storeVoucherMap = {};
      _appliedStoreVouchers.forEach((spId, code) {
        if (code.trim().isNotEmpty) {
          storeVoucherMap[spId.toString()] = code.trim().toUpperCase();
        }
      });

      final StringMap payMethodsMap = {};
      _paymentMethods.forEach((spId, method) {
        payMethodsMap[spId.toString()] = method;
      });

      final JsonMap bodyPayload = {
        'mode': widget.mode,
        'user_address_id': _selectedAddress!.id,
        'address_id': _selectedAddress!.id,
        'idempotency_key': _idempotencyKey ?? '',
        if (_priceSignature != null) 'price_signature': _priceSignature,
        if (_appliedPlatformVoucherCode.isNotEmpty)
          'platform_voucher_code': _appliedPlatformVoucherCode,
        if (_appliedShippingVoucherCode.isNotEmpty)
          'shipping_voucher_code': _appliedShippingVoucherCode,
        'use_storkia_coins': _useStorkiaCoins,
        if (_useStorkiaCoins && _coinsToUse > 0) 'coins_to_use': _coinsToUse,
        'seller_notes': notesMap,
        'store_voucher_codes': storeVoucherMap,
        'payment_methods': payMethodsMap,
      };

      if (widget.mode == 'cart' && _checkoutData != null) {
        bodyPayload['cart_ids'] = _extractList(_checkoutData!['cart_ids']);
      } else if (widget.mode == 'buy_now' && widget.buyNowData != null) {
        bodyPayload.addAll(widget.buyNowData!);
      }

      final response = await ApiService.httpClient
          .post(
            Uri.parse('$_domain/api/v1/checkout/store'),
            headers: ApiService.buildHeaders(widget.token, isJson: true),
            body: json.encode(bodyPayload),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        HapticFeedback.mediumImpact();
        syncAllBuyerCounters(ref, widget.token);
        final orderPayload = data['data'] is Map
            ? JsonMap.from(data['data'] as Map)
            : <String, dynamic>{
                'id': data['order_id'],
                'order_number': 'ORD-${data['order_id']}',
                'total_amount': _checkoutData?['overall_total'] ?? 0,
              };
        Navigator.pushReplacement(
          context,
          StorkRoute.fade(
            CheckoutSuccessScreen(
              orderData: orderPayload,
              baseUrl: _domain,
              token: widget.token,
            ),
          ),
        );
      } else {
        String errMsg = data is Map
            ? (data['message']?.toString() ?? 'Failed to place order.')
            : 'Failed to place order.';
        if (data is Map &&
            data['errors'] is Map &&
            (data['errors'] as Map).isNotEmpty) {
          final firstErr = (data['errors'] as Map).values.first;
          if (firstErr is List && firstErr.isNotEmpty) {
            errMsg = firstErr.first.toString();
          }
        }
        _showError(errMsg);
        if (data is Map &&
            data['errors'] is Map &&
            (data['errors'] as Map).containsKey('price_changed')) {
          _fetchPreview(silent: true);
        }
      }
    } catch (_) {
      _showError('Network error occurred while placing order.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _isLoading = false;
      _isSyncingPreview = false;
      _isSubmitting = false;
    });
    _showPopupNotification(message, isError: true);
  }

  Future<void> _navigateAndSelectAddress() async {
    final result = await Navigator.push(
      context,
      StorkRoute.fade(
        AddressSelectionScreen(
          baseUrl: _domain,
          token: widget.token,
          selectedAddressId: _selectedAddress?.id,
        ),
      ),
    );
    if (result is Address) {
      setState(() => _selectedAddress = result);
      _fetchPreview(addressId: result.id, silent: true);
    } else {
      _fetchPreview(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> packages =
        _extractList(_checkoutData?['seller_packages']);
    final blockers = _checkoutBlockers;
    final bool canSubmit = !_isSubmitting && blockers.isEmpty;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Checkout'),
        ),
      ),
      body: _isLoading && _checkoutData == null
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : _checkoutData == null
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: StorkTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shopping_bag_outlined,
                            size: 36,
                            color: StorkTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Unable to load checkout details.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        if (_lastErrorMessage != null &&
                            _lastErrorMessage!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            _lastErrorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _fetchPreview(silent: false),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _buildAddressSection(),
                    const SizedBox(height: 12),
                    for (int i = 0; i < packages.length; i++)
                      if (packages[i] is Map)
                        _buildSellerPackage(
                          i,
                          JsonMap.from(packages[i] as Map),
                        ),
                    _buildPlatformAndShippingVouchersSection(),
                    const SizedBox(height: 12),
                    _buildStorkiaCoinsRedemptionSection(),
                    const SizedBox(height: 12),
                    _buildCheckoutSummaryCard(),
                    const SizedBox(height: 24),
                  ],
                ),
      bottomNavigationBar: _checkoutData == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: StorkTheme.surface,
                border: const Border(
                    top: BorderSide(color: StorkTheme.borderSubtle)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (blockers.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: StorkTheme.warning.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: StorkTheme.warning.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: Color(0xFF92400E),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Incomplete Step: ${blockers.first}',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF92400E),
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final totalCol = Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Payable Amount',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: StorkTheme.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '\u20B1${_formatMoney(_checkoutData!['overall_total'])}',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: StorkTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        );

                        final placeOrderBtn = Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient:
                                canSubmit ? StorkTheme.brandGradient : null,
                            color: canSubmit ? null : StorkTheme.surfaceSubtle,
                            borderRadius: BorderRadius.circular(14),
                            border: canSubmit
                                ? null
                                : Border.all(color: StorkTheme.borderSubtle),
                          ),
                          child: ElevatedButton(
                            onPressed:
                                _isSubmitting ? null : _handlePlaceOrderTap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: canSubmit
                                  ? Colors.white
                                  : StorkTheme.textMuted,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 22),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Place Order',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        );

                        if (constraints.maxWidth < 290) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              totalCol,
                              const SizedBox(height: 8),
                              placeOrderBtn,
                            ],
                          );
                        }

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: totalCol),
                            const SizedBox(width: 12),
                            placeOrderBtn,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAddressSection() {
    final unserviceableReason = _firstPackageUnserviceableReason ??
        (!_isAddressServiceable
            ? 'Delivery to this municipality/province is currently unserviceable by our partner logistics hubs and barangay riders. Please select another address.'
            : null);
    final isAddressLong = (_selectedAddress?.fullAddress.length ?? 0) > 85 ||
        (unserviceableReason != null && unserviceableReason.length > 95);

    return GestureDetector(
      onTap: _navigateAndSelectAddress,
      onLongPress: _selectedAddress != null
          ? () => _copyTextWithToast(
                '${_selectedAddress!.recipientName} (${_selectedAddress!.phoneNumber}) - ${_selectedAddress!.fullAddress}',
                'Delivery Address',
              )
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: StorkTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: unserviceableReason != null || _selectedAddress == null
                ? StorkTheme.danger
                : StorkTheme.borderSubtle,
            width: unserviceableReason != null || _selectedAddress == null
                ? 1.5
                : 1,
          ),
          boxShadow: StorkTheme.softCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: StorkTheme.brandGradient,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Delivery Address',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
                        ),
                      ),
                      if (_selectedAddress != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: unserviceableReason == null
                                ? StorkTheme.success.withValues(alpha: 0.12)
                                : StorkTheme.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            unserviceableReason == null
                                ? 'Serviceable Route Verified'
                                : 'Unserviceable Route',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: unserviceableReason == null
                                  ? StorkTheme.success
                                  : StorkTheme.danger,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _navigateAndSelectAddress,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    _selectedAddress != null ? 'Change' : 'Add Address',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selectedAddress != null) ...[
              Text(
                '${_selectedAddress!.recipientName}  \u2022  +63 ${_selectedAddress!.phoneNumber.replaceFirst(RegExp(r'^(\+?63|0)'), '')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: StorkTheme.textMain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _selectedAddress!.fullAddress,
                maxLines: isAddressLong && !_isAddressExpanded ? 2 : 8,
                overflow: isAddressLong && !_isAddressExpanded
                    ? TextOverflow.ellipsis
                    : TextOverflow.visible,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: StorkTheme.textMuted,
                  height: 1.38,
                ),
              ),
              if (unserviceableReason != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StorkTheme.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unserviceableReason,
                    maxLines: isAddressLong && !_isAddressExpanded ? 3 : 8,
                    overflow: isAddressLong && !_isAddressExpanded
                        ? TextOverflow.ellipsis
                        : TextOverflow.visible,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: StorkTheme.danger,
                    ),
                  ),
                ),
              ],
              if (isAddressLong) ...[
                const SizedBox(height: 4),
                _buildSeeMoreToggle(
                  isExpanded: _isAddressExpanded,
                  moreLabel: 'See More Address Details',
                  onTap: () =>
                      setState(() => _isAddressExpanded = !_isAddressExpanded),
                ),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Please add or select a delivery address to place your order.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: StorkTheme.danger,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerPackage(int pkgIndex, JsonMap pkg) {
    final sellerProfile = pkg['seller_profile'] is Map
        ? JsonMap.from(pkg['seller_profile'] as Map)
        : <String, dynamic>{};
    final int spId = int.tryParse(sellerProfile['id']?.toString() ?? '0') ?? 0;
    final String storeName =
        sellerProfile['business_name']?.toString() ?? 'Store';
    final List<dynamic> items = _extractList(pkg['items']);
    final JsonMap shipping = pkg['shipping'] is Map
        ? JsonMap.from(pkg['shipping'] as Map)
        : <String, dynamic>{};
    final storeVouchers = _availableVouchers
        .where((v) =>
            v['scope']?.toString() == 'store' &&
            int.tryParse(v['seller_profile_id']?.toString() ?? '0') == spId)
        .toList();
    final selectedMethod = _paymentMethods[spId] ?? 'COD';
    final currentStoreCode = _appliedStoreVouchers[spId] ?? '';
    final String recommendedStoreCode = _recommendedStoreVouchers[spId] ?? '';
    final double pkgSubtotal =
        double.tryParse(pkg['subtotal']?.toString() ?? '0') ?? 0.0;
    final double bundleDisc =
        double.tryParse(pkg['bundle_discount']?.toString() ?? '0') ?? 0.0;
    final double eligibleStoreBase =
        (pkgSubtotal - bundleDisc).clamp(0.0, double.infinity);
    final String? bundleTitle = pkg['bundle_title']?.toString();
    final double storeDisc =
        double.tryParse(pkg['store_discount']?.toString() ?? '0') ?? 0.0;
    final double platDisc =
        double.tryParse(pkg['platform_discount']?.toString() ?? '0') ?? 0.0;
    final int pkgCoinsUsed =
        int.tryParse(pkg['coins_used']?.toString() ?? '0') ?? 0;
    final double pkgCoinsDisc =
        double.tryParse(pkg['coins_discount']?.toString() ?? '0') ?? 0.0;
    final double origShippingFee = double.tryParse(
            (pkg['original_shipping_fee'] ??
                    shipping['shipping_fee'] ??
                    pkg['net_shipping_fee'])
                .toString()) ??
        0.0;
    final double pkgShipDiscount =
        double.tryParse(pkg['shipping_discount']?.toString() ?? '0') ?? 0.0;
    final double netShippingFee =
        double.tryParse(pkg['net_shipping_fee']?.toString() ?? '0') ?? 0.0;
    final double? distKm = shipping['distance_km'] != null
        ? double.tryParse(shipping['distance_km'].toString())
        : null;
    final String tierLabel = (shipping['tier_label'] ?? '').toString().trim();
    final bool isPkgServiceable = shipping['is_serviceable'] != false;
    final String? pkgUnserviceableReason =
        shipping['unserviceable_reason']?.toString();
    final String routeBadgeLabel =
        (shipping['route_badge_label'] ?? '').toString().trim();

    final bool itemsExpanded = _expandedPackageItems.contains(spId);
    final List<dynamic> visibleItems =
        (items.length > 2 && !itemsExpanded) ? items.take(2).toList() : items;
    final bool breakdownExpanded = _expandedPackageBreakdowns.contains(spId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: !isPkgServiceable
              ? StorkTheme.danger.withValues(alpha: 0.65)
              : StorkTheme.borderSubtle,
          width: !isPkgServiceable ? 1.5 : 1,
        ),
        boxShadow: StorkTheme.softCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: StorkTheme.surfaceSubtle.withValues(alpha: 0.7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: StorkTheme.brandGradient,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Package ${pkgIndex + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (distKm != null && distKm > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: StorkTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '~${distKm.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.primaryDark,
                              ),
                            ),
                          ),
                        Text(
                          'From: ${sellerProfile['municipality'] ?? ''}, ${sellerProfile['province'] ?? ''}',
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
                if (isPkgServiceable && routeBadgeLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: StorkTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: StorkTheme.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.route_rounded,
                          size: 13,
                          color: StorkTheme.success,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Route: $routeBadgeLabel',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isPkgServiceable)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: StorkTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: StorkTheme.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                (pkgUnserviceableReason != null &&
                        pkgUnserviceableReason.trim().isNotEmpty)
                    ? pkgUnserviceableReason
                    : 'Unserviceable route between seller and your delivery address.',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: StorkTheme.danger,
                ),
              ),
            ),
          for (final rawItem in visibleItems)
            if (rawItem is Map)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: StorkTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: StorkTheme.borderSubtle),
                      ),
                      child: rawItem['image_path'] != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.network(
                                ApiConfig.storageUrl(
                                    rawItem['image_path'].toString(), _domain),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: StorkTheme.textMuted,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.inventory_2_outlined,
                              color: StorkTheme.textMuted,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (rawItem['product'] is Map
                                    ? rawItem['product']['name']?.toString()
                                    : null) ??
                                '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.textMain,
                            ),
                          ),
                          if (rawItem['variant_name'] != null)
                            Text(
                              [
                                rawItem['variant_name'],
                                rawItem['sub_variant_name']
                              ]
                                  .where((e) =>
                                      e != null && e.toString().isNotEmpty)
                                  .join(' / '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                          if (rawItem['pricing_label'] != null &&
                              rawItem['pricing_label'].toString() !=
                                  'Regular' &&
                              rawItem['pricing_label'].toString() !=
                                  'Regular Price')
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color:
                                      StorkTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  rawItem['pricing_label'].toString(),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: StorkTheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '\u20B1${_formatMoney(rawItem['discounted_unit_price'])} \u00D7 ${rawItem['quantity']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: StorkTheme.textMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '\u20B1${_formatMoney(rawItem['line_total'])}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          if (items.length > 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: _buildSeeMoreToggle(
                isExpanded: itemsExpanded,
                moreLabel:
                    'See More Items (+${items.length - 2} more in package)',
                lessLabel: 'See Less Items',
                onTap: () {
                  setState(() {
                    if (itemsExpanded) {
                      _expandedPackageItems.remove(spId);
                    } else {
                      _expandedPackageItems.add(spId);
                    }
                  });
                },
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bundleDisc > 0) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: StorkTheme.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: StorkTheme.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Bundle Applied: ${bundleTitle ?? 'Store Bundle Deal'}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.success,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '-\u20B1${_formatMoney(bundleDisc)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: StorkTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      'PAYMENT METHOD FOR ${storeName.toUpperCase()} *',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          StorkRoute.fade(
                            PointsRewardsScreen(
                              baseUrl: _domain,
                              token: widget.token,
                              initialTab: 1,
                            ),
                          ),
                        ).then((_) => _fetchPreview(silent: true));
                      },
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text(
                        '+ Top Up E-Wallet',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final codCard = InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _paymentMethods[spId] = 'COD');
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedMethod == 'COD'
                              ? StorkTheme.primary.withValues(alpha: 0.06)
                              : StorkTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selectedMethod == 'COD'
                                ? StorkTheme.primary
                                : StorkTheme.borderSubtle,
                            width: selectedMethod == 'COD' ? 1.8 : 1,
                          ),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cash on Delivery',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Pay cash to Rider',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );

                    final walletCard = InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _paymentMethods[spId] = 'WALLET');
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedMethod == 'WALLET'
                              ? StorkTheme.primaryDark.withValues(alpha: 0.07)
                              : StorkTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selectedMethod == 'WALLET'
                                ? StorkTheme.primaryDark
                                : StorkTheme.borderSubtle,
                            width: selectedMethod == 'WALLET' ? 1.8 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Storkia E-Wallet',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bal: \u20B1${_formatMoney(_buyerWalletBalance)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: StorkTheme.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (constraints.maxWidth < 290) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          codCard,
                          const SizedBox(height: 8),
                          walletCard,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: codCard),
                        const SizedBox(width: 10),
                        Expanded(child: walletCard),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _buildSeeMoreToggle(
                        isExpanded: breakdownExpanded,
                        moreLabel: currentStoreCode.isNotEmpty
                            ? 'See More (Voucher $currentStoreCode, Note & Breakdown)'
                            : 'See More (Store Voucher, Note & Breakdown)',
                        lessLabel: 'See Less Package Options',
                        onTap: () {
                          setState(() {
                            if (breakdownExpanded) {
                              _expandedPackageBreakdowns.remove(spId);
                            } else {
                              _expandedPackageBreakdowns.add(spId);
                            }
                          });
                        },
                      ),
                    ),
                    Text(
                      '\u20B1${_formatMoney(pkg['total'])}',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: StorkTheme.primary,
                      ),
                    ),
                  ],
                ),
                if (breakdownExpanded) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _noteControllers[spId],
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: 'Optional Note to $storeName',
                      counterText: '',
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'STORE VOUCHER ($storeName)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
                        ),
                      ),
                      if (recommendedStoreCode.isNotEmpty)
                        Text(
                          'Preferred: $recommendedStoreCode',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (storeVouchers.isNotEmpty) ...[
                    SizedBox(
                      height: 84,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildVoucherOptionChip(
                            code: '',
                            title: 'No Store Voucher',
                            subtitle: 'Skip discount',
                            isSelected: currentStoreCode.isEmpty,
                            isMostPreferred: false,
                            activeColor: StorkTheme.primary,
                            onTap: () {
                              if (currentStoreCode.isEmpty) return;
                              HapticFeedback.selectionClick();
                              setState(() {
                                _touchedSlots.add('store_$spId');
                                _appliedStoreVouchers[spId] = '';
                                _storeVoucherControllers[spId]?.clear();
                              });
                              _applyOptimisticLocalCalculation();
                              _fetchPreview(silent: true);
                            },
                          ),
                          for (final sv in storeVouchers)
                            _buildVoucherOptionChip(
                              code: sv['code']?.toString() ?? '',
                              title:
                                  sv['badge_label']?.toString() ?? 'STORE OFF',
                              subtitle:
                                  'Min \u20B1${_formatMoney(sv['min_spend'])}',
                              isSelected: currentStoreCode.toUpperCase() ==
                                  (sv['code']?.toString().toUpperCase() ?? ''),
                              isMostPreferred:
                                  sv['is_most_preferred'] == true ||
                                      (recommendedStoreCode.isNotEmpty &&
                                          recommendedStoreCode ==
                                              (sv['code']
                                                      ?.toString()
                                                      .toUpperCase() ??
                                                  '')),
                              activeColor: StorkTheme.primary,
                              onTap: () {
                                final c = sv['code']?.toString() ?? '';
                                if (currentStoreCode.toUpperCase() ==
                                    c.toUpperCase()) {
                                  return;
                                }
                                final minSpend = double.tryParse(
                                        sv['min_spend']?.toString() ?? '0') ??
                                    0.0;
                                if (eligibleStoreBase + 0.0001 < minSpend) {
                                  _showPopupNotification(
                                    'Voucher $c requires a minimum spend of \u20B1${_formatMoney(minSpend)} at $storeName.',
                                    isError: true,
                                  );
                                  return;
                                }
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _touchedSlots.add('store_$spId');
                                  _appliedStoreVouchers[spId] = c;
                                  _storeVoucherControllers[spId]?.text = c;
                                });
                                _applyOptimisticLocalCalculation();
                                _fetchPreview(silent: true);
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final voucherInput = TextField(
                        controller: _storeVoucherControllers[spId],
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'Or enter store voucher code...',
                        ),
                      );
                      final applyBtn = ElevatedButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          final entered = _storeVoucherControllers[spId]!
                              .text
                              .trim()
                              .toUpperCase();
                          if (entered.isEmpty && currentStoreCode.isEmpty) {
                            _showPopupNotification(
                              'Please enter a store voucher code before tapping Apply.',
                              isError: true,
                            );
                            return;
                          }
                          if (entered.isNotEmpty) {
                            final known = _findAvailableVoucher(
                              entered,
                              scope: 'store',
                              sellerId: spId,
                            );
                            if (known != null) {
                              final minSpend = double.tryParse(
                                      known['min_spend']?.toString() ?? '0') ??
                                  0.0;
                              if (eligibleStoreBase + 0.0001 < minSpend) {
                                _showPopupNotification(
                                  'Voucher $entered requires a minimum spend of \u20B1${_formatMoney(minSpend)} at $storeName.',
                                  isError: true,
                                );
                                return;
                              }
                            }
                          }
                          setState(() {
                            _touchedSlots.add('store_$spId');
                            _appliedStoreVouchers[spId] = entered;
                          });
                          _applyOptimisticLocalCalculation();
                          _fetchPreview(silent: true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StorkTheme.primaryDark,
                        ),
                        child: const Text('Apply'),
                      );

                      if (constraints.maxWidth < 290) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            voucherInput,
                            const SizedBox(height: 8),
                            applyBtn,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: voucherInput),
                          const SizedBox(width: 8),
                          applyBtn,
                        ],
                      );
                    },
                  ),
                  const Divider(height: 22),
                  _buildPackageRow('Package Subtotal:',
                      '\u20B1${_formatMoney(pkgSubtotal)}'),
                  if (tierLabel.isNotEmpty)
                    _buildPackageRow('Shipping Tier:', tierLabel),
                  if (routeBadgeLabel.isNotEmpty)
                    _buildPackageRow('Verified Route:', routeBadgeLabel,
                        valueColor: StorkTheme.success),
                  if (storeDisc > 0)
                    _buildPackageRow('Store Voucher Discount:',
                        '-\u20B1${_formatMoney(storeDisc)}',
                        valueColor: StorkTheme.primary),
                  if (platDisc > 0)
                    _buildPackageRow('Platform Voucher Share:',
                        '-\u20B1${_formatMoney(platDisc)}',
                        valueColor: StorkTheme.primaryDark),
                  if (pkgCoinsDisc > 0)
                    _buildPackageRow('Coins Offset ($pkgCoinsUsed Coins):',
                        '-\u20B1${_formatMoney(pkgCoinsDisc)}',
                        valueColor: StorkTheme.primary),
                  if (pkgShipDiscount > 0) ...[
                    _buildPackageRow('Original Shipping Fee:',
                        '\u20B1${_formatMoney(origShippingFee)}'),
                    _buildPackageRow('Shipping Voucher Share:',
                        '-\u20B1${_formatMoney(pkgShipDiscount)}',
                        valueColor: StorkTheme.success),
                  ],
                  _buildPackageRow(
                    'Net Shipping Fee:',
                    '\u20B1${_formatMoney(netShippingFee)}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: StorkTheme.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: valueColor ?? StorkTheme.textMain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformAndShippingVouchersSection() {
    final platformVouchers = _availableVouchers
        .where((v) => v['scope']?.toString() == 'platform')
        .toList();
    final shippingVouchers = _availableVouchers
        .where((v) => v['scope']?.toString() == 'shipping')
        .toList();
    final double netAfterStore = _resolveNetAfterStoreDiscounts();

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform & Free Shipping Vouchers',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Auto-applied best vouchers or tap to customize.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _buildSeeMoreToggle(
                isExpanded: _isVouchersSectionExpanded,
                moreLabel: 'See More',
                lessLabel: 'See Less',
                onTap: () => setState(() =>
                    _isVouchersSectionExpanded = !_isVouchersSectionExpanded),
              ),
            ],
          ),
          if (!_isVouchersSectionExpanded &&
              (_appliedPlatformVoucherCode.isNotEmpty ||
                  _appliedShippingVoucherCode.isNotEmpty)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_appliedPlatformVoucherCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: StorkTheme.primaryDark.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: StorkTheme.primaryDark.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      'Platform: $_appliedPlatformVoucherCode',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                  ),
                if (_appliedShippingVoucherCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: StorkTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: StorkTheme.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'Shipping: $_appliedShippingVoucherCode',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.success,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (_isVouchersSectionExpanded) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Text(
                  'PLATFORM VOUCHER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                if (_recommendedPlatformVoucher.isNotEmpty)
                  Text(
                    'Preferred: $_recommendedPlatformVoucher',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (platformVouchers.isNotEmpty) ...[
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildVoucherOptionChip(
                      code: '',
                      title: 'No Platform Voucher',
                      subtitle: 'Skip discount',
                      isSelected: _appliedPlatformVoucherCode.isEmpty,
                      isMostPreferred: false,
                      activeColor: StorkTheme.primaryDark,
                      onTap: () {
                        if (_appliedPlatformVoucherCode.isEmpty) return;
                        HapticFeedback.selectionClick();
                        setState(() {
                          _touchedSlots.add('platform');
                          _appliedPlatformVoucherCode = '';
                          _platformVoucherController.clear();
                        });
                        _applyOptimisticLocalCalculation();
                        _fetchPreview(silent: true);
                      },
                    ),
                    for (final pv in platformVouchers)
                      _buildVoucherOptionChip(
                        code: pv['code']?.toString() ?? '',
                        title: pv['badge_label']?.toString() ?? 'PLATFORM OFF',
                        subtitle: 'Min \u20B1${_formatMoney(pv['min_spend'])}',
                        isSelected: _appliedPlatformVoucherCode.toUpperCase() ==
                            (pv['code']?.toString().toUpperCase() ?? ''),
                        isMostPreferred: pv['is_most_preferred'] == true ||
                            (_recommendedPlatformVoucher.isNotEmpty &&
                                _recommendedPlatformVoucher ==
                                    (pv['code']?.toString().toUpperCase() ??
                                        '')),
                        activeColor: StorkTheme.primaryDark,
                        onTap: () {
                          final c = pv['code']?.toString() ?? '';
                          if (_appliedPlatformVoucherCode.toUpperCase() ==
                              c.toUpperCase()) {
                            return;
                          }
                          final minSpend = double.tryParse(
                                  pv['min_spend']?.toString() ?? '0') ??
                              0.0;
                          if (netAfterStore + 0.0001 < minSpend) {
                            _showPopupNotification(
                              'Platform voucher $c requires a minimum spend of \u20B1${_formatMoney(minSpend)}.',
                              isError: true,
                            );
                            return;
                          }
                          HapticFeedback.selectionClick();
                          setState(() {
                            _touchedSlots.add('platform');
                            _appliedPlatformVoucherCode = c;
                            _platformVoucherController.text = c;
                          });
                          _applyOptimisticLocalCalculation();
                          _fetchPreview(silent: true);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _platformVoucherController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'Enter Platform Voucher Code...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    final entered =
                        _platformVoucherController.text.trim().toUpperCase();
                    if (entered.isEmpty &&
                        _appliedPlatformVoucherCode.isEmpty) {
                      _showPopupNotification(
                        'Please enter a platform voucher code before tapping Apply.',
                        isError: true,
                      );
                      return;
                    }
                    setState(() {
                      _touchedSlots.add('platform');
                      _appliedPlatformVoucherCode = entered;
                    });
                    _applyOptimisticLocalCalculation();
                    _fetchPreview(silent: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StorkTheme.primaryDark,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Text(
                  'FREE SHIPPING VOUCHER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                if (_recommendedShippingVoucher.isNotEmpty)
                  Text(
                    'Preferred: $_recommendedShippingVoucher',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (shippingVouchers.isNotEmpty) ...[
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildVoucherOptionChip(
                      code: '',
                      title: 'No Shipping Voucher',
                      subtitle: 'Standard shipping',
                      isSelected: _appliedShippingVoucherCode.isEmpty,
                      isMostPreferred: false,
                      activeColor: StorkTheme.primary,
                      onTap: () {
                        if (_appliedShippingVoucherCode.isEmpty) return;
                        HapticFeedback.selectionClick();
                        setState(() {
                          _touchedSlots.add('shipping');
                          _appliedShippingVoucherCode = '';
                          _shippingVoucherController.clear();
                        });
                        _applyOptimisticLocalCalculation();
                        _fetchPreview(silent: true);
                      },
                    ),
                    for (final shv in shippingVouchers)
                      _buildVoucherOptionChip(
                        code: shv['code']?.toString() ?? '',
                        title: shv['badge_label']?.toString() ?? 'FREE SHIP',
                        subtitle: 'Min \u20B1${_formatMoney(shv['min_spend'])}',
                        isSelected: _appliedShippingVoucherCode.toUpperCase() ==
                            (shv['code']?.toString().toUpperCase() ?? ''),
                        isMostPreferred: shv['is_most_preferred'] == true ||
                            (_recommendedShippingVoucher.isNotEmpty &&
                                _recommendedShippingVoucher ==
                                    (shv['code']?.toString().toUpperCase() ??
                                        '')),
                        activeColor: StorkTheme.primary,
                        onTap: () {
                          final c = shv['code']?.toString() ?? '';
                          if (_appliedShippingVoucherCode.toUpperCase() ==
                              c.toUpperCase()) {
                            return;
                          }
                          final minSpend = double.tryParse(
                                  shv['min_spend']?.toString() ?? '0') ??
                              0.0;
                          final overallSub = double.tryParse(
                                  _checkoutData?['overall_subtotal']
                                          ?.toString() ??
                                      '0') ??
                              0.0;
                          if (overallSub + 0.0001 < minSpend) {
                            _showPopupNotification(
                              'Shipping voucher $c requires a minimum spend of \u20B1${_formatMoney(minSpend)}.',
                              isError: true,
                            );
                            return;
                          }
                          HapticFeedback.selectionClick();
                          setState(() {
                            _touchedSlots.add('shipping');
                            _appliedShippingVoucherCode = c;
                            _shippingVoucherController.text = c;
                          });
                          _applyOptimisticLocalCalculation();
                          _fetchPreview(silent: true);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _shippingVoucherController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'Enter Shipping Voucher Code...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    final entered =
                        _shippingVoucherController.text.trim().toUpperCase();
                    if (entered.isEmpty &&
                        _appliedShippingVoucherCode.isEmpty) {
                      _showPopupNotification(
                        'Please enter a shipping voucher code before tapping Apply.',
                        isError: true,
                      );
                      return;
                    }
                    setState(() {
                      _touchedSlots.add('shipping');
                      _appliedShippingVoucherCode = entered;
                    });
                    _applyOptimisticLocalCalculation();
                    _fetchPreview(silent: true);
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoucherOptionChip({
    required String code,
    required String title,
    required String subtitle,
    required bool isSelected,
    required bool isMostPreferred,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 170,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.08)
              : StorkTheme.surfaceSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : StorkTheme.borderSubtle,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    code.isNotEmpty ? code : 'NONE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? activeColor : StorkTheme.primaryDark,
                    ),
                  ),
                ),
                if (isMostPreferred)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: StorkTheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '\u2605 BEST',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: StorkTheme.textMain,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: StorkTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorkiaCoinsRedemptionSection() {
    final bool canRedeemCoins = _maxRedeemableCoins >= _minRedeemableCoins;
    final double maxPesoDiscount = _maxRedeemableCoins * 0.10;

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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: StorkTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.monetization_on_rounded,
                  color: StorkTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Redeem Storkia Coins ($_buyerCoinsBalance available)',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      canRedeemCoins
                          ? 'Use up to $_maxRedeemableCoins Coins (-\u20B1${_formatMoney(maxPesoDiscount)}) \u2022 10 Coins = \u20B11.00'
                          : (_buyerCoinsBalance > 0 &&
                                  _buyerCoinsBalance < _minRedeemableCoins
                              ? 'Minimum $_minRedeemableCoins Coins (\u20B11.00) required to redeem at checkout'
                              : 'No redeemable coins for this order'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                activeThumbColor: StorkTheme.primary,
                value: _useStorkiaCoins && canRedeemCoins,
                onChanged: (val) {
                  if (!canRedeemCoins) {
                    _showPopupNotification(
                      _buyerCoinsBalance < _minRedeemableCoins
                          ? 'You need at least $_minRedeemableCoins Storkia Coins (\u20B11.00) in your balance to redeem coins at checkout.'
                          : 'No Storkia Coins can be applied to this order.',
                      isError: true,
                    );
                    return;
                  }
                  HapticFeedback.selectionClick();
                  setState(() {
                    _useStorkiaCoins = val;
                    _coinsToUse = val ? _maxRedeemableCoins : 0;
                    _coinsInputController.text = '$_coinsToUse';
                  });
                  _applyOptimisticLocalCalculation();
                  _fetchPreview(silent: true);
                },
              ),
            ],
          ),
          if (_useStorkiaCoins && canRedeemCoins) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _coinsInputController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText:
                          'Coins to redeem ($_minRedeemableCoins - $_maxRedeemableCoins)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final parsed =
                        int.tryParse(_coinsInputController.text.trim()) ?? 0;
                    if (parsed < _minRedeemableCoins) {
                      _showPopupNotification(
                        'Minimum redeemable amount is $_minRedeemableCoins Storkia Coins (\u20B11.00).',
                        isError: true,
                      );
                      setState(() {
                        _coinsToUse = _minRedeemableCoins;
                        _coinsInputController.text = '$_coinsToUse';
                      });
                    } else if (parsed > _maxRedeemableCoins) {
                      _showPopupNotification(
                        'Maximum redeemable for this order is $_maxRedeemableCoins Storkia Coins.',
                        isError: false,
                        isWarning: true,
                      );
                      setState(() {
                        _coinsToUse = _maxRedeemableCoins;
                        _coinsInputController.text = '$_coinsToUse';
                      });
                    } else {
                      setState(() => _coinsToUse = parsed);
                    }
                    _applyOptimisticLocalCalculation();
                    _fetchPreview(silent: true);
                  },
                  child: const Text('Apply Coins'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckoutSummaryCard() {
    if (_checkoutData == null) return const SizedBox.shrink();
    final double overallSub = double.tryParse(
            _checkoutData!['overall_subtotal']?.toString() ?? '0') ??
        0.0;
    final double overallShip = double.tryParse(
            _checkoutData!['overall_shipping']?.toString() ?? '0') ??
        0.0;
    final double storeDisc = double.tryParse(
            _checkoutData!['overall_store_discount']?.toString() ?? '0') ??
        0.0;
    final double platDisc = double.tryParse(
            _checkoutData!['overall_platform_discount']?.toString() ?? '0') ??
        0.0;
    final double shipDisc = double.tryParse(
            _checkoutData!['overall_shipping_discount']?.toString() ?? '0') ??
        0.0;
    final int coinsUsed =
        int.tryParse(_checkoutData!['overall_coins_used']?.toString() ?? '0') ??
            0;
    final double coinsDisc = double.tryParse(
            _checkoutData!['overall_coins_discount']?.toString() ?? '0') ??
        0.0;
    final double overallTotal =
        double.tryParse(_checkoutData!['overall_total']?.toString() ?? '0') ??
            0.0;
    final int totalItems =
        int.tryParse(_checkoutData!['total_items']?.toString() ?? '1') ?? 1;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Order Summary',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: StorkTheme.primaryDark,
                ),
              ),
              _buildSeeMoreToggle(
                isExpanded: _isOrderSummaryExpanded,
                moreLabel: 'See Breakdown',
                lessLabel: 'See Less',
                onTap: () => setState(
                    () => _isOrderSummaryExpanded = !_isOrderSummaryExpanded),
              ),
            ],
          ),
          if (_isOrderSummaryExpanded) ...[
            const SizedBox(height: 12),
            _buildPackageRow('Merchandise Subtotal ($totalItems item(s)):',
                '\u20B1${_formatMoney(overallSub)}'),
            _buildPackageRow(
                'Shipping Subtotal:', '\u20B1${_formatMoney(overallShip)}'),
            if (storeDisc > 0)
              _buildPackageRow(
                'Store Voucher / Bundle Discount:',
                '-\u20B1${_formatMoney(storeDisc)}',
                valueColor: StorkTheme.primary,
              ),
            if (platDisc > 0)
              _buildPackageRow(
                'Platform Voucher ($_appliedPlatformVoucherCode):',
                '-\u20B1${_formatMoney(platDisc)}',
                valueColor: StorkTheme.primaryDark,
              ),
            if (shipDisc > 0)
              _buildPackageRow(
                'Shipping Voucher ($_appliedShippingVoucherCode):',
                '-\u20B1${_formatMoney(shipDisc)}',
                valueColor: StorkTheme.success,
              ),
            if (coinsDisc > 0)
              _buildPackageRow(
                'Storkia Coins ($coinsUsed Coins):',
                '-\u20B1${_formatMoney(coinsDisc)}',
                valueColor: StorkTheme.primary,
              ),
            const Divider(height: 20),
          ] else
            const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Payable Amount:',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: StorkTheme.primaryDark,
                ),
              ),
              Text(
                '\u20B1${_formatMoney(overallTotal)}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: StorkTheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}