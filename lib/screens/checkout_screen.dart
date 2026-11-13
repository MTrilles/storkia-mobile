import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/address_model.dart';
import '../providers/global_counters_provider.dart';
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
  Timer? _autoSyncTimer;
  String? _lastErrorMessage;

  JsonMap? _checkoutData;
  Address? _selectedAddress;
  bool _isAddressServiceable = true;
  String? _idempotencyKey;
  String? _priceSignature;
  double _buyerWalletBalance = 0.0;

  int _buyerCoinsBalance = 0;
  int _maxRedeemableCoins = 0;
  int _minRedeemableCoins = 10;
  bool _useStorkiaCoins = false;
  int _coinsToUse = 0;
  String? _coinsValidationMessage;
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

  List<String> _voucherNotices = [];
  List<JsonMap> _availableVouchers = [];

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchPreview(silent: false);
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isSubmitting && !_isLoading && !_isSyncingPreview) {
        _fetchPreview(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
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
      final response = await http.get(
        Uri.parse('$_domain/api/v1/addresses'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 6));

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

      final response = await http
          .post(
            Uri.parse('$_domain/api/v1/checkout/preview'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
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
          _voucherNotices = [for (final e in rawNotices) e.toString()];

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
      } else if (!silent) {
        final msg = body is Map
            ? (body['message']?.toString() ??
                'Failed to load checkout preview.')
            : 'Failed to load checkout preview.';
        _lastErrorMessage = msg;
        _showError(msg);
      }
    } catch (_) {
      if (!silent) {
        _lastErrorMessage = 'Network error occurred while loading checkout.';
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

  Future<void> _placeOrder() async {
    if (_selectedAddress == null) {
      _showError('Please select a delivery address.');
      return;
    }
    if (!_isAddressServiceable) {
      _showError(
          'Your selected delivery address is currently unserviceable by our partner logistics hubs.');
      return;
    }
    if (!_hasSufficientWalletBalance) {
      final shortfall = _totalWalletRequired - _buyerWalletBalance;
      _showError(
          'Insufficient Storkia E-Wallet balance. Please top up ₱${_formatMoney(shortfall)} or choose Cash on Delivery (COD).');
      return;
    }

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

      final response = await http
          .post(
            Uri.parse('$_domain/api/v1/checkout/store'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode(bodyPayload),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
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
    setState(() {
      _isLoading = false;
      _isSyncingPreview = false;
      _isSubmitting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: StorkTheme.danger,
      ),
    );
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
    final bool canSubmit = !_isSubmitting &&
        _selectedAddress != null &&
        _isAddressServiceable &&
        _hasSufficientWalletBalance;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Checkout'),
        bottom: _isSyncingPreview
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: StorkTheme.primary,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: _isLoading && _checkoutData == null
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : _checkoutData == null
              ? Center(
                  child: Padding(
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
                    if (_voucherNotices.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: StorkTheme.warning.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: StorkTheme.warning.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final n in _voucherNotices)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      size: 15,
                                      color: Color(0xFF92400E),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        n,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: StorkTheme.textMain,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Payable Amount',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: StorkTheme.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '₱${_formatMoney(_checkoutData!['overall_total'])}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: StorkTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: canSubmit ? StorkTheme.brandGradient : null,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ElevatedButton(
                        onPressed: canSubmit ? _placeOrder : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 26),
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
                            : const Text('Place Order'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAddressSection() {
    return GestureDetector(
      onTap: _navigateAndSelectAddress,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: StorkTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: !_isAddressServiceable
                ? StorkTheme.danger
                : StorkTheme.borderSubtle,
            width: !_isAddressServiceable ? 1.5 : 1,
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
                const Expanded(
                  child: Text(
                    'Delivery Address',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primaryDark,
                    ),
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
                '${_selectedAddress!.recipientName}  •  +63 ${_selectedAddress!.phoneNumber.replaceFirst(RegExp(r'^(\+?63|0)'), '')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: StorkTheme.textMain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _selectedAddress!.fullAddress,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: StorkTheme.textMuted,
                  height: 1.38,
                ),
              ),
              if (!_isAddressServiceable) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StorkTheme.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Delivery to this municipality/province is currently unserviceable by our partner logistics hubs. Please select another address.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: StorkTheme.danger,
                    ),
                  ),
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

    final double bundleDisc =
        double.tryParse(pkg['bundle_discount']?.toString() ?? '0') ?? 0.0;
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

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: StorkTheme.surfaceSubtle.withValues(alpha: 0.7),
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
                      Expanded(
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
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'From: ${sellerProfile['municipality'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: StorkTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final rawItem in items)
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
                                  '₱${_formatMoney(rawItem['discounted_unit_price'])} × ${rawItem['quantity']}',
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
                                '₱${_formatMoney(rawItem['line_total'])}',
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
                          '-₱${_formatMoney(bundleDisc)}',
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
                    height: 78,
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
                            title: sv['badge_label']?.toString() ?? 'STORE OFF',
                            subtitle: 'Min ₱${_formatMoney(sv['min_spend'])}',
                            isSelected: currentStoreCode.toUpperCase() ==
                                (sv['code']?.toString().toUpperCase() ?? ''),
                            isMostPreferred: sv['is_most_preferred'] == true ||
                                (recommendedStoreCode.isNotEmpty &&
                                    recommendedStoreCode ==
                                        (sv['code']?.toString().toUpperCase() ??
                                            '')),
                            activeColor: StorkTheme.primary,
                            onTap: () {
                              final c = sv['code']?.toString() ?? '';
                              if (currentStoreCode.toUpperCase() ==
                                  c.toUpperCase()) {
                                return;
                              }
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _storeVoucherControllers[spId],
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'Or enter store voucher code...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _touchedSlots.add('store_$spId');
                          _appliedStoreVouchers[spId] =
                              _storeVoucherControllers[spId]!
                                  .text
                                  .trim()
                                  .toUpperCase();
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
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'PAYMENT METHOD FOR ${storeName.toUpperCase()} *',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
                        ),
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
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setState(() => _paymentMethods[spId] = 'COD'),
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
                                'Pay cash upon delivery',
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
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setState(() => _paymentMethods[spId] = 'WALLET'),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selectedMethod == 'WALLET'
                                ? StorkTheme.primaryDark.withValues(alpha: 0.08)
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
                                'Bal: ₱${_formatMoney(_buyerWalletBalance)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: _hasSufficientWalletBalance
                                      ? StorkTheme.success
                                      : StorkTheme.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),
                if (storeDisc > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Store Voucher ($currentStoreCode)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: StorkTheme.success,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '-₱${_formatMoney(storeDisc)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                if (platDisc > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'Platform Voucher Share',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B21A8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '-₱${_formatMoney(platDisc)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6B21A8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                if (pkgCoinsUsed > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Storkia Coins Redeemed ($pkgCoinsUsed Coins)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '-₱${_formatMoney(pkgCoinsDisc)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Shipping (${shipping['tier_label'] ?? 'Standard'} • ${pkg['total_weight']} kg)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (pkgShipDiscount > 0) ...[
                          Text(
                            '₱${_formatMoney(origShippingFee)}',
                            style: const TextStyle(
                              fontSize: 11,
                              decoration: TextDecoration.lineThrough,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          netShippingFee <= 0.001
                              ? 'FREE (₱0.00)'
                              : '₱${_formatMoney(netShippingFee)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: pkgShipDiscount > 0
                                ? const Color(0xFF047857)
                                : StorkTheme.textMain,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Package Total',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '₱${_formatMoney(pkg['total'])}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
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
    );
  }

  Widget _buildStorkiaCoinsRedemptionSection() {
    final bool canRedeem = _maxRedeemableCoins >= _minRedeemableCoins;
    final double currentDiscount = _coinsToUse * 0.10;
    final double maxDiscount = _maxRedeemableCoins * 0.10;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _useStorkiaCoins
              ? const Color(0xFFD97706)
              : StorkTheme.borderSubtle,
        ),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Redeem Storkia Coins (10 Coins = ₱1.00)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    Text(
                      canRedeem
                          ? 'Balance: $_buyerCoinsBalance Coins • Max usable: $_maxRedeemableCoins Coins (-₱${_formatMoney(maxDiscount)})'
                          : 'Balance: $_buyerCoinsBalance Coins (Minimum $_minRedeemableCoins coins required)',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                activeThumbColor: const Color(0xFFD97706),
                value: _useStorkiaCoins && canRedeem,
                onChanged: !canRedeem
                    ? null
                    : (val) {
                        setState(() {
                          _useStorkiaCoins = val;
                          _coinsValidationMessage = null;
                          if (val && _coinsToUse < _minRedeemableCoins) {
                            _coinsToUse = _maxRedeemableCoins;
                            _coinsInputController.text = '$_coinsToUse';
                          }
                        });
                        _applyOptimisticLocalCalculation();
                        _fetchPreview(silent: true);
                      },
              ),
            ],
          ),
          if (_useStorkiaCoins && canRedeem) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Using $_coinsToUse Coins',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.textMain,
                  ),
                ),
                Text(
                  'Discount: -₱${_formatMoney(currentDiscount)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
            if (_maxRedeemableCoins > _minRedeemableCoins)
              Slider(
                value: _coinsToUse
                    .clamp(_minRedeemableCoins, _maxRedeemableCoins)
                    .toDouble(),
                min: _minRedeemableCoins.toDouble(),
                max: _maxRedeemableCoins.toDouble(),
                divisions:
                    (_maxRedeemableCoins - _minRedeemableCoins).clamp(1, 500),
                activeColor: const Color(0xFFD97706),
                onChanged: (val) {
                  final rounded = val.round();
                  setState(() {
                    _coinsToUse = rounded;
                    _coinsInputController.text = '$rounded';
                    _coinsValidationMessage = null;
                  });
                  _applyOptimisticLocalCalculation();
                },
                onChangeEnd: (_) => _fetchPreview(silent: true),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _coinsInputController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText:
                          'Coins ($_minRedeemableCoins - $_maxRedeemableCoins)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _coinsToUse = _maxRedeemableCoins;
                      _coinsInputController.text = '$_maxRedeemableCoins';
                      _coinsValidationMessage = null;
                    });
                    _applyOptimisticLocalCalculation();
                    _fetchPreview(silent: true);
                  },
                  child: const Text('Max'),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: () {
                    final parsed =
                        int.tryParse(_coinsInputController.text.trim());
                    if (parsed == null) {
                      setState(() {
                        _coinsValidationMessage =
                            'Enter a valid whole number between $_minRedeemableCoins and $_maxRedeemableCoins.';
                      });
                      return;
                    }
                    String? note;
                    if (parsed < _minRedeemableCoins) {
                      note =
                          'Minimum redeemable is $_minRedeemableCoins coins.';
                    } else if (parsed > _maxRedeemableCoins) {
                      note =
                          'Maximum redeemable for this order is $_maxRedeemableCoins coins (25% cap).';
                    }
                    final clamped =
                        parsed.clamp(_minRedeemableCoins, _maxRedeemableCoins);
                    setState(() {
                      _coinsToUse = clamped;
                      _coinsInputController.text = '$clamped';
                      _coinsValidationMessage = note;
                    });
                    _applyOptimisticLocalCalculation();
                    _fetchPreview(silent: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
            if (_coinsValidationMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _coinsValidationMessage!,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ],
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Platform & Free Shipping Vouchers',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
              ),
              Text(
                'Auto-Picks Best Savings',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: StorkTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'PLATFORM VOUCHER (ADMIN-SPONSORED)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF581C87),
                  ),
                ),
              ),
              if (_recommendedPlatformVoucher.isNotEmpty)
                Text(
                  'Preferred: $_recommendedPlatformVoucher',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B21A8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (platformVouchers.isNotEmpty) ...[
            SizedBox(
              height: 78,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildVoucherOptionChip(
                    code: '',
                    title: 'No Platform Voucher',
                    subtitle: 'None',
                    isSelected: _appliedPlatformVoucherCode.isEmpty,
                    isMostPreferred: false,
                    activeColor: const Color(0xFF6B21A8),
                    onTap: () {
                      if (_appliedPlatformVoucherCode.isEmpty) return;
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
                      subtitle: 'Min ₱${_formatMoney(pv['min_spend'])}',
                      isSelected: _appliedPlatformVoucherCode.toUpperCase() ==
                          (pv['code']?.toString().toUpperCase() ?? ''),
                      isMostPreferred: pv['is_most_preferred'] == true ||
                          (_recommendedPlatformVoucher.isNotEmpty &&
                              _recommendedPlatformVoucher ==
                                  (pv['code']?.toString().toUpperCase() ?? '')),
                      activeColor: const Color(0xFF6B21A8),
                      onTap: () {
                        final c = pv['code']?.toString() ?? '';
                        if (_appliedPlatformVoucherCode.toUpperCase() ==
                            c.toUpperCase()) {
                          return;
                        }
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
                  setState(() {
                    _touchedSlots.add('platform');
                    _appliedPlatformVoucherCode =
                        _platformVoucherController.text.trim().toUpperCase();
                  });
                  _applyOptimisticLocalCalculation();
                  _fetchPreview(silent: true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B21A8),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'FREE SHIPPING VOUCHER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF065F46),
                  ),
                ),
              ),
              if (_recommendedShippingVoucher.isNotEmpty)
                Text(
                  'Preferred: $_recommendedShippingVoucher',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF047857),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (shippingVouchers.isNotEmpty) ...[
            SizedBox(
              height: 78,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildVoucherOptionChip(
                    code: '',
                    title: 'No Shipping Voucher',
                    subtitle: 'None',
                    isSelected: _appliedShippingVoucherCode.isEmpty,
                    isMostPreferred: false,
                    activeColor: const Color(0xFF047857),
                    onTap: () {
                      if (_appliedShippingVoucherCode.isEmpty) return;
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
                      subtitle: 'Min ₱${_formatMoney(shv['min_spend'])}',
                      isSelected: _appliedShippingVoucherCode.toUpperCase() ==
                          (shv['code']?.toString().toUpperCase() ?? ''),
                      isMostPreferred: shv['is_most_preferred'] == true ||
                          (_recommendedShippingVoucher.isNotEmpty &&
                              _recommendedShippingVoucher ==
                                  (shv['code']?.toString().toUpperCase() ??
                                      '')),
                      activeColor: const Color(0xFF047857),
                      onTap: () {
                        final c = shv['code']?.toString() ?? '';
                        if (_appliedShippingVoucherCode.toUpperCase() ==
                            c.toUpperCase()) {
                          return;
                        }
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
                  setState(() {
                    _touchedSlots.add('shipping');
                    _appliedShippingVoucherCode =
                        _shippingVoucherController.text.trim().toUpperCase();
                  });
                  _applyOptimisticLocalCalculation();
                  _fetchPreview(silent: true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF047857),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
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
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMostPreferred)
              Container(
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '★ MOST PREFERRED',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            Text(
              code.isNotEmpty ? '$code • $title' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isSelected ? activeColor : StorkTheme.textMain,
              ),
            ),
            Text(
              subtitle,
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
  }

  Widget _buildCheckoutSummaryCard() {
    final storeDisc = double.tryParse(
            _checkoutData!['overall_store_discount']?.toString() ?? '0') ??
        0.0;
    final platDisc = double.tryParse(
            _checkoutData!['overall_platform_discount']?.toString() ?? '0') ??
        0.0;
    final shipDisc = double.tryParse(
            _checkoutData!['overall_shipping_discount']?.toString() ?? '0') ??
        0.0;
    final int overallCoinsUsed =
        int.tryParse(_checkoutData!['overall_coins_used']?.toString() ?? '0') ??
            0;
    final double coinsDisc = double.tryParse(
            _checkoutData!['overall_coins_discount']?.toString() ?? '0') ??
        0.0;

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
          const Text(
            'Checkout Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          const Divider(height: 22),
          _buildSummaryRow(
            'Merchandise Subtotal (${_checkoutData!['total_items'] ?? 0} items)',
            '₱${_formatMoney(_checkoutData!['overall_subtotal'])}',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Original Shipping Subtotal',
            '₱${_formatMoney(_checkoutData!['overall_shipping'])}',
          ),
          if (storeDisc > 0) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Store & Bundle Discounts',
              '-₱${_formatMoney(storeDisc)}',
              valueColor: StorkTheme.success,
            ),
          ],
          if (platDisc > 0) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Platform Voucher ($_appliedPlatformVoucherCode)',
              '-₱${_formatMoney(platDisc)}',
              valueColor: const Color(0xFF6B21A8),
            ),
          ],
          if (shipDisc > 0) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Shipping Voucher ($_appliedShippingVoucherCode)',
              '-₱${_formatMoney(shipDisc)}',
              valueColor: const Color(0xFF047857),
            ),
          ],
          if (coinsDisc > 0) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Storkia Coins ($overallCoinsUsed Coins)',
              '-₱${_formatMoney(coinsDisc)}',
              valueColor: const Color(0xFFB45309),
            ),
          ],
          if (_totalWalletRequired > 0) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Payable via Storkia E-Wallet',
              '₱${_formatMoney(_totalWalletRequired)}',
              valueColor: _hasSufficientWalletBalance
                  ? StorkTheme.primaryDark
                  : StorkTheme.danger,
            ),
          ],
          const Divider(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Total Payable Amount',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.textMain,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₱${_formatMoney(_checkoutData!['overall_total'])}',
                style: const TextStyle(
                  fontSize: 20,
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

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: StorkTheme.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: valueColor ?? StorkTheme.textMain,
          ),
        ),
      ],
    );
  }
}
