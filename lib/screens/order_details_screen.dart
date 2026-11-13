import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../providers/global_counters_provider.dart';
import 'cart_screen.dart';
import 'identity_verification_screen.dart';
import 'leave_review_screen.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StringMap = Map<String, String>;
typedef XFileList = List<XFile>;

class OrderDetailsScreen extends ConsumerStatefulWidget {
  final int orderId;
  final String baseUrl;
  final String token;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  Timer? _autoSyncTimer;

  JsonMap? _orderData;
  JsonMap? _liveTrackingData;
  JsonMap _cancellationQuota = {
    'window_days': 7,
    'limit_by_buyer': 5,
    'used_by_buyer': 0,
    'remaining_buyer': 5,
  };
  bool _isIdentityVerified = false;
  int _unreadDeliveryChatCount = 0;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchAllOrderData();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchAllOrderData(silent: true);
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
      _fetchAllOrderData(silent: true);
    }
  }

  List<dynamic> _extractList(dynamic value) {
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[];
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

  Future<void> _fetchAllOrderData({bool silent = false}) async {
    await Future.wait([
      _fetchOrderDetails(silent: silent),
      _fetchLiveTrackingSilently(),
    ]);
  }

  Future<void> _fetchOrderDetails({bool silent = false}) async {
    if (!silent && _orderData == null) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/orders/${widget.orderId}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['success'] == true && data['data'] is Map) {
          final orderMap = JsonMap.from(data['data'] as Map);
          setState(() {
            _orderData = orderMap;
            if (data['cancellation_quota'] is Map) {
              _cancellationQuota =
                  JsonMap.from(data['cancellation_quota'] as Map);
            }
            _isIdentityVerified = data['is_identity_verified'] == true;
            _unreadDeliveryChatCount = int.tryParse(
                    (data['unread_delivery_chat_count'] ??
                            orderMap['unread_delivery_chat_count'] ??
                            '0')
                        .toString()) ??
                0;
            _isLoading = false;
          });
          return;
        }
      }
      if (!silent) _showError('Failed to load order details.');
    } catch (_) {
      if (!silent) _showError('Network error occurred.');
    }
  }

  Future<void> _fetchLiveTrackingSilently() async {
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/orders/${widget.orderId}/live-tracking'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted || response.statusCode != 200) return;
      final body = json.decode(response.body);
      if (body is Map && body['success'] == true && body['data'] is Map) {
        setState(() {
          _liveTrackingData = JsonMap.from(body['data'] as Map);
        });
      }
    } catch (_) {}
  }

  Future<void> _openOrderInvoiceModal() async {
    _showLoadingDialog();
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/orders/${widget.orderId}/invoice'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      Navigator.pop(context);

      final body = json.decode(response.body);
      if (response.statusCode == 200 &&
          body is Map &&
          body['success'] == true &&
          body['data'] is Map) {
        final inv = JsonMap.from(body['data'] as Map);
        final List<dynamic> items = inv['items'] is List
            ? List<dynamic>.from(inv['items'] as List)
            : <dynamic>[];

        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: StorkTheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (modalContext) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              maxChildSize: 0.94,
              minChildSize: 0.5,
              builder: (ctx, scrollCtrl) {
                return ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: StorkTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                inv['invoice_number']?.toString() ?? 'INVOICE',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              Text(
                                'Issued: ${inv['issued_at'] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: StorkTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                        'Store:', inv['seller']?['business_name'] ?? 'Store'),
                    _buildInfoRow(
                        'Store Address:', inv['seller']?['address'] ?? ''),
                    _buildInfoRow('Buyer:',
                        inv['buyer']?['recipient_name'] ?? 'Recipient'),
                    _buildInfoRow(
                        'Delivery Address:', inv['buyer']?['address'] ?? ''),
                    _buildInfoRow('Payment Method:',
                        '${inv['payment_method'] ?? 'COD'} (${inv['payment_status'] ?? ''})'),
                    if (inv['payment_reference'] != null)
                      _buildInfoRow(
                          'Payment Ref:', inv['payment_reference'].toString()),
                    const Divider(height: 24),
                    const Text(
                      'ORDER LINE ITEMS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final raw in items)
                      if (raw is Map)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${raw['product_name']}${raw['variant'] != null ? ' (${raw['variant']})' : ''} × ${raw['quantity']}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '₱${_formatMoney(raw['line_total'])}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    const Divider(height: 24),
                    _buildInfoRow('Original Merchandise Subtotal:',
                        '₱${_formatMoney(inv['original_subtotal'])}'),
                    if ((double.tryParse(
                                inv['store_voucher_discount']?.toString() ??
                                    '0') ??
                            0) >
                        0)
                      _buildInfoRow('Store & Bundle Discount:',
                          '-₱${_formatMoney(inv['store_voucher_discount'])}'),
                    if ((double.tryParse(
                                inv['platform_voucher_discount']?.toString() ??
                                    '0') ??
                            0) >
                        0)
                      _buildInfoRow('Platform Voucher Discount:',
                          '-₱${_formatMoney(inv['platform_voucher_discount'])}'),
                    if ((double.tryParse(
                                inv['coins_discount_amount']?.toString() ??
                                    '0') ??
                            0) >
                        0)
                      _buildInfoRow(
                          'Storkia Coins (${inv['coins_used']} Coins):',
                          '-₱${_formatMoney(inv['coins_discount_amount'])}'),
                    _buildInfoRow('Net Merchandise Subtotal:',
                        '₱${_formatMoney(inv['net_subtotal'])}'),
                    if ((double.tryParse(
                                inv['shipping_voucher_discount']?.toString() ??
                                    '0') ??
                            0) >
                        0) ...[
                      _buildInfoRow('Original Shipping Fee:',
                          '₱${_formatMoney(inv['original_shipping_fee'])}'),
                      _buildInfoRow('Shipping Voucher Discount:',
                          '-₱${_formatMoney(inv['shipping_voucher_discount'])}'),
                    ],
                    _buildInfoRow('Net Shipping Fee:',
                        '₱${_formatMoney(inv['net_shipping_fee'])}'),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Invoice Amount',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        Text(
                          '₱${_formatMoney(inv['total_amount'])}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: StorkTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      } else {
        _showError('Unable to load order invoice.');
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showError('Network error occurred.');
    }
  }

  Future<void> _openDeliveryRiderChatSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _DeliveryRiderChatBottomSheet(
        orderId: widget.orderId,
        domain: _domain,
        token: widget.token,
      ),
    );
    if (mounted) {
      setState(() => _unreadDeliveryChatCount = 0);
    }
  }

  Future<void> _confirmReceipt() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Confirm Order Received',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: const Text(
          'Have you inspected and received the items in good condition? Confirming will complete this order, award your Storkia Coins cashback, and release payment.',
          style: TextStyle(fontSize: 13.5, color: StorkTheme.textMain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: StorkTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StorkTheme.success,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm Receipt'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _showLoadingDialog();
    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/orders/${widget.orderId}/confirm-receipt'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      Navigator.pop(context);

      final data = json.decode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        syncAllBuyerCounters(ref, widget.token);
        _showSuccess(
          data['message']?.toString() ?? 'Order confirmed and completed!',
        );
        _fetchAllOrderData(silent: true);
      } else {
        _showError(
          data is Map
              ? (data['message']?.toString() ?? 'Failed to confirm receipt.')
              : 'Failed to confirm receipt.',
        );
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showError('Network error occurred.');
    }
  }

  Future<void> _switchFlaggedOrderToCod() async {
    _showLoadingDialog();
    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/orders/${widget.orderId}/switch-to-cod'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      Navigator.pop(context);

      final data = json.decode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        syncAllBuyerCounters(ref, widget.token);
        _showSuccess(
          data['message']?.toString() ??
              'Order switched to Cash on Delivery (COD)!',
        );
        _fetchAllOrderData(silent: true);
      } else {
        _showError(
          data is Map
              ? (data['message']?.toString() ??
                  'Failed to switch order to COD.')
              : 'Failed to switch order to COD.',
        );
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showError('Network error occurred.');
    }
  }

  Future<void> _cancelFlaggedPaymentOrder() async {
    _showLoadingDialog();
    try {
      final response = await http.post(
        Uri.parse(
            '$_domain/api/v1/orders/${widget.orderId}/cancel-flagged-payment'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      Navigator.pop(context);

      final data = json.decode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        syncAllBuyerCounters(ref, widget.token);
        _showSuccess(
          data['message']?.toString() ?? 'Order cancelled immediately.',
        );
        _fetchAllOrderData(silent: true);
      } else {
        _showError(
          data is Map
              ? (data['message']?.toString() ?? 'Unable to cancel order.')
              : 'Unable to cancel order.',
        );
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showError('Network error occurred.');
    }
  }

  Future<void> _openPreShipmentCancelSheet() async {
    const List<String> reasons = [
      'Changed my mind',
      'Need to change delivery address',
      'Forgot to apply voucher code',
      'Ordered wrong item or variation',
    ];
    String selectedReason = reasons.first;
    final notesController = TextEditingController();
    bool isSubmitting = false;
    String? modalError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: StorkTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Cancel Order #${_orderData?['seller_order_number'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SELECT CANCELLATION REASON *',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final reason in reasons)
                      InkWell(
                        onTap: () =>
                            setModalState(() => selectedReason = reason),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                selectedReason == reason
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: selectedReason == reason
                                    ? StorkTheme.primary
                                    : StorkTheme.textMuted,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Additional Notes (Optional)',
                        counterText: '',
                        fillColor: StorkTheme.surfaceSubtle,
                      ),
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        modalError!,
                        style: const TextStyle(
                          color: StorkTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(modalContext),
                            child: const Text('Keep Order'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StorkTheme.danger,
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    setModalState(() {
                                      isSubmitting = true;
                                      modalError = null;
                                    });
                                    try {
                                      final response = await http
                                          .post(
                                            Uri.parse(
                                                '$_domain/api/v1/orders/${widget.orderId}/cancel'),
                                            headers: {
                                              'Authorization':
                                                  'Bearer ${widget.token}',
                                              'Accept': 'application/json',
                                              'Content-Type':
                                                  'application/json',
                                            },
                                            body: json.encode({
                                              'cancel_reason': selectedReason,
                                              'cancel_notes':
                                                  notesController.text.trim(),
                                            }),
                                          )
                                          .timeout(ApiConfig.requestTimeout);

                                      final data = json.decode(response.body);
                                      if (response.statusCode == 200 &&
                                          data is Map &&
                                          data['success'] == true) {
                                        syncAllBuyerCounters(ref, widget.token);
                                        if (modalContext.mounted) {
                                          Navigator.pop(modalContext);
                                        }
                                        _showSuccess(
                                          data['message']?.toString() ??
                                              'Order cancelled successfully.',
                                        );
                                        _fetchAllOrderData(silent: true);
                                      } else {
                                        String err = data is Map
                                            ? (data['message']?.toString() ??
                                                'Unable to cancel order.')
                                            : 'Unable to cancel order.';
                                        if (data is Map &&
                                            data['errors'] is Map &&
                                            (data['errors'] as Map)
                                                .isNotEmpty) {
                                          final first = (data['errors'] as Map)
                                              .values
                                              .first;
                                          if (first is List &&
                                              first.isNotEmpty) {
                                            err = first.first.toString();
                                          }
                                        }
                                        setModalState(() => modalError = err);
                                      }
                                    } catch (_) {
                                      setModalState(() => modalError =
                                          'Network error occurred.');
                                    } finally {
                                      if (modalContext.mounted) {
                                        setModalState(
                                            () => isSubmitting = false);
                                      }
                                    }
                                  },
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Confirm Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openReturnRefundModal() async {
    _showLoadingDialog();

    List<JsonMap> reasonCatalog = [
      {
        'key': 'damaged_item',
        'label': 'Damaged or defective item',
        'resolution': 'return_refund',
        'hint': 'Item arrived broken, damaged, or malfunctioning.',
        'refund_only_forced': false,
      },
      {
        'key': 'wrong_item',
        'label': 'Wrong item or variation received',
        'resolution': 'return_refund',
        'hint': 'Received a different product, size, or color than ordered.',
        'refund_only_forced': false,
      },
      {
        'key': 'missing_parts',
        'label': 'Missing parts or incomplete quantity',
        'resolution': 'return_refund',
        'hint': 'Some accessories or ordered units were missing.',
        'refund_only_forced': false,
      },
      {
        'key': 'not_as_described',
        'label': 'Item does not match description/photos',
        'resolution': 'return_refund',
        'hint': 'Material or specifications differ significantly from listing.',
        'refund_only_forced': false,
      },
      {
        'key': 'did_not_receive',
        'label': 'Parcel marked delivered but not received',
        'resolution': 'refund_only',
        'hint': 'Order shows delivered but package never arrived.',
        'refund_only_forced': true,
      },
      {
        'key': 'empty_parcel',
        'label': 'Received an empty package',
        'resolution': 'refund_only',
        'hint': 'Outer packaging arrived with no item inside.',
        'refund_only_forced': true,
      },
    ];

    String defaultAccountName = '';
    String defaultAccountNumber = '';
    bool identityVerified = _isIdentityVerified;
    String? blockerMessage;

    try {
      final res = await http.get(
        Uri.parse('$_domain/api/v1/orders/${widget.orderId}/return'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (mounted) Navigator.pop(context);

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body is Map && body['data'] is Map) {
          final d = JsonMap.from(body['data'] as Map);
          identityVerified = d['identity_verified'] == true;
          blockerMessage = d['blocker']?.toString();
          defaultAccountName = d['default_account_name']?.toString() ?? '';
          defaultAccountNumber = d['default_account_number']?.toString() ?? '';

          if (d['reasons'] is List && (d['reasons'] as List).isNotEmpty) {
            final StringMap fallbackLabels = {
              for (final item in reasonCatalog)
                item['key'].toString(): item['label'].toString(),
            };
            reasonCatalog = [
              for (final r in (d['reasons'] as List))
                if (r is Map)
                  {
                    'key': r['key']?.toString() ?? 'damaged_item',
                    'label': r['label']?.toString() ??
                        fallbackLabels[r['key']?.toString() ?? ''] ??
                        (r['key']
                                ?.toString()
                                .replaceAll('_', ' ')
                                .toUpperCase() ??
                            'Issue'),
                    'resolution':
                        r['resolution']?.toString() ?? 'return_refund',
                    'hint': r['hint']?.toString() ?? '',
                    'refund_only_forced': r['refund_only_forced'] == true,
                  },
            ];
          }
        }
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }

    if (!mounted) return;

    if (!identityVerified) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'Valid ID Verification Required',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: StorkTheme.primaryDark,
            ),
          ),
          content: const Text(
            'To protect both buyers and merchants from fraudulent claims, Storkia requires an approved Valid Government ID on your account before submitting a Return & Refund request.\n\nPlease complete Identity Verification first.',
            style: TextStyle(
              fontSize: 13.5,
              color: StorkTheme.textMain,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  StorkRoute.fade(
                    IdentityVerificationScreen(
                      baseUrl: _domain,
                      token: widget.token,
                    ),
                  ),
                ).then((_) => _fetchAllOrderData(silent: true));
              },
              child: const Text('Verify ID Now'),
            ),
          ],
        ),
      );
      return;
    }

    if (blockerMessage != null && blockerMessage.isNotEmpty) {
      _showError(blockerMessage);
      return;
    }

    String selectedCategoryKey = reasonCatalog.first['key'].toString();
    String selectedResolution =
        reasonCatalog.first['refund_only_forced'] == true
            ? 'refund_only'
            : 'return_refund';
    String refundMethod = 'WALLET';

    final accountNameCtrl = TextEditingController(text: defaultAccountName);
    final accountPhoneCtrl = TextEditingController(text: defaultAccountNumber);
    final reasonCtrl = TextEditingController();
    XFileList evidenceFiles = <XFile>[];
    String? formError;
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final JsonMap activeReasonObj = reasonCatalog.firstWhere(
              (r) => r['key'] == selectedCategoryKey,
              orElse: () => reasonCatalog.first,
            );
            final bool isRefundOnlyForced =
                activeReasonObj['refund_only_forced'] == true;
            final String activeHint = activeReasonObj['hint']?.toString() ?? '';

            if (isRefundOnlyForced && selectedResolution != 'refund_only') {
              selectedResolution = 'refund_only';
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: StorkTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Request Return & Refund',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: StorkTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: StorkTheme.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              '✓ Valid Government ID Verified',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.success,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Refundable: ₱${_formatMoney(_orderData?['total_amount'])}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategoryKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Issue Category *',
                      ),
                      items: [
                        for (final r in reasonCatalog)
                          DropdownMenuItem<String>(
                            value: r['key'].toString(),
                            child: Text(
                              r['label'].toString(),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          final match = reasonCatalog.firstWhere(
                            (r) => r['key'] == val,
                            orElse: () => reasonCatalog.first,
                          );
                          setModalState(() {
                            selectedCategoryKey = val;
                            if (match['refund_only_forced'] == true) {
                              selectedResolution = 'refund_only';
                            } else {
                              selectedResolution =
                                  match['resolution']?.toString() ??
                                      'return_refund';
                            }
                            formError = null;
                          });
                        }
                      },
                    ),
                    if (activeHint.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        activeHint,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'REQUESTED RESOLUTION *',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (!isRefundOnlyForced) ...[
                          Expanded(
                            child: InkWell(
                              onTap: () => setModalState(
                                  () => selectedResolution = 'return_refund'),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: selectedResolution == 'return_refund'
                                      ? StorkTheme.primary
                                          .withValues(alpha: 0.08)
                                      : StorkTheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selectedResolution == 'return_refund'
                                        ? StorkTheme.primary
                                        : StorkTheme.borderSubtle,
                                    width: selectedResolution == 'return_refund'
                                        ? 1.6
                                        : 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Return & Refund',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: selectedResolution == 'return_refund'
                                        ? StorkTheme.primary
                                        : StorkTheme.textMain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(
                                () => selectedResolution = 'refund_only'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 8),
                              decoration: BoxDecoration(
                                color: selectedResolution == 'refund_only'
                                    ? StorkTheme.primaryDark
                                        .withValues(alpha: 0.08)
                                    : StorkTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedResolution == 'refund_only'
                                      ? StorkTheme.primaryDark
                                      : StorkTheme.borderSubtle,
                                  width: selectedResolution == 'refund_only'
                                      ? 1.6
                                      : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                isRefundOnlyForced
                                    ? 'Refund Only (No Physical Return Needed)'
                                    : 'Refund Only',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: selectedResolution == 'refund_only'
                                      ? StorkTheme.primaryDark
                                      : StorkTheme.textMain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'REFUND PAYOUT DESTINATION *',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                setModalState(() => refundMethod = 'WALLET'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: refundMethod == 'WALLET'
                                    ? StorkTheme.primary.withValues(alpha: 0.08)
                                    : StorkTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: refundMethod == 'WALLET'
                                      ? StorkTheme.primary
                                      : StorkTheme.borderSubtle,
                                  width: refundMethod == 'WALLET' ? 1.6 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Instant E-Wallet',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: refundMethod == 'WALLET'
                                      ? StorkTheme.primary
                                      : StorkTheme.textMain,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                setModalState(() => refundMethod = 'GCASH'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: refundMethod == 'GCASH'
                                    ? StorkTheme.info.withValues(alpha: 0.08)
                                    : StorkTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: refundMethod == 'GCASH'
                                      ? StorkTheme.info
                                      : StorkTheme.borderSubtle,
                                  width: refundMethod == 'GCASH' ? 1.6 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'GCash Refund',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: refundMethod == 'GCASH'
                                      ? StorkTheme.info
                                      : StorkTheme.textMain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (refundMethod == 'GCASH') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: accountNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'GCash Account Holder Name *',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: accountPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'GCash Mobile Number *',
                          prefixText: '+63 ',
                          hintText: '09171234567 or 9171234567',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 3,
                      maxLength: 1000,
                      onChanged: (_) {
                        if (formError != null) {
                          setModalState(() => formError = null);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Describe the Issue (10+ characters) *',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickMultiImage(
                          imageQuality: 85,
                        );
                        if (picked.isNotEmpty) {
                          if (picked.length > 5) {
                            setModalState(() {
                              formError =
                                  'You may upload a maximum of 5 evidence photos.';
                            });
                            return;
                          }
                          for (final f in picked) {
                            final len = await f.length();
                            if (len > 5 * 1024 * 1024) {
                              setModalState(() {
                                formError =
                                    'Each evidence photo must not exceed 5MB.';
                              });
                              return;
                            }
                          }
                          setModalState(() {
                            evidenceFiles = picked;
                            formError = null;
                          });
                        }
                      },
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(
                        evidenceFiles.isEmpty
                            ? 'Upload 1 to 5 Evidence Photos (Max 5MB)*'
                            : '${evidenceFiles.length} evidence photo(s) selected',
                      ),
                    ),
                    if (evidenceFiles.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in evidenceFiles)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(f.path),
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (formError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        formError!,
                        style: const TextStyle(
                          color: StorkTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StorkTheme.danger,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final reasonText = reasonCtrl.text.trim();
                                if (reasonText.length < 10) {
                                  setModalState(() {
                                    formError =
                                        'Please provide at least 10 characters explaining the issue.';
                                  });
                                  return;
                                }

                                String normalizedGcashPhone =
                                    defaultAccountNumber;
                                String resolvedAccountName = defaultAccountName;

                                if (refundMethod == 'GCASH') {
                                  resolvedAccountName =
                                      accountNameCtrl.text.trim();
                                  if (resolvedAccountName.isEmpty) {
                                    setModalState(() {
                                      formError =
                                          'Please enter your GCash account holder name.';
                                    });
                                    return;
                                  }

                                  final rawDigits = accountPhoneCtrl.text
                                      .trim()
                                      .replaceAll(RegExp(r'\D'), '');
                                  if (!RegExp(r'^0?9\d{9}$')
                                      .hasMatch(rawDigits)) {
                                    setModalState(() {
                                      formError =
                                          'Enter a valid 11-digit (09XXXXXXXXX) or 10-digit (9XXXXXXXXX) GCash number.';
                                    });
                                    return;
                                  }
                                  normalizedGcashPhone =
                                      rawDigits.startsWith('9') &&
                                              rawDigits.length == 10
                                          ? '0$rawDigits'
                                          : rawDigits;
                                } else {
                                  if (normalizedGcashPhone.isEmpty) {
                                    normalizedGcashPhone = '09170000000';
                                  }
                                  if (resolvedAccountName.isEmpty) {
                                    resolvedAccountName = 'Buyer E-Wallet';
                                  }
                                }

                                if (evidenceFiles.isEmpty ||
                                    evidenceFiles.length > 5) {
                                  setModalState(() {
                                    formError =
                                        'Please attach between 1 and 5 evidence photos.';
                                  });
                                  return;
                                }

                                setModalState(() {
                                  isSubmitting = true;
                                  formError = null;
                                });

                                try {
                                  final req = http.MultipartRequest(
                                    'POST',
                                    Uri.parse(
                                        '$_domain/api/v1/orders/${widget.orderId}/return'),
                                  );
                                  req.headers['Authorization'] =
                                      'Bearer ${widget.token}';
                                  req.headers['Accept'] = 'application/json';

                                  req.fields['reason_category'] =
                                      selectedCategoryKey;
                                  req.fields['requested_resolution'] =
                                      selectedResolution;
                                  req.fields['reason'] = reasonText;
                                  req.fields['refund_payout_method'] =
                                      refundMethod;
                                  req.fields['refund_method'] = refundMethod;
                                  req.fields['refund_account_name'] =
                                      resolvedAccountName;
                                  req.fields['refund_account_number'] =
                                      normalizedGcashPhone;

                                  for (final f in evidenceFiles) {
                                    req.files.add(
                                      await http.MultipartFile.fromPath(
                                        'evidence_photos[]',
                                        f.path,
                                      ),
                                    );
                                  }

                                  final streamed = await req
                                      .send()
                                      .timeout(ApiConfig.requestTimeout);
                                  final res =
                                      await http.Response.fromStream(streamed);
                                  final data = json.decode(res.body);

                                  if ((res.statusCode == 200 ||
                                          res.statusCode == 201) &&
                                      data is Map &&
                                      data['success'] == true) {
                                    syncAllBuyerCounters(ref, widget.token);
                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                    }
                                    _showSuccess(
                                      data['message']?.toString() ??
                                          'Return & Refund request submitted.',
                                    );
                                    _fetchAllOrderData(silent: true);
                                  } else {
                                    String err = data is Map
                                        ? (data['message']?.toString() ??
                                            'Failed to submit return request.')
                                        : 'Failed to submit return request.';
                                    if (data is Map &&
                                        data['errors'] is Map &&
                                        (data['errors'] as Map).isNotEmpty) {
                                      final first =
                                          (data['errors'] as Map).values.first;
                                      if (first is List && first.isNotEmpty) {
                                        err = first.first.toString();
                                      }
                                    }
                                    setModalState(() => formError = err);
                                  }
                                } catch (_) {
                                  setModalState(() =>
                                      formError = 'Network error occurred.');
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(() => isSubmitting = false);
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Submit Return & Refund'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openEscalateReturnDialog(int? returnRequestId) async {
    final noteCtrl = TextEditingController();
    bool isSubmitting = false;
    String? modalError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: StorkTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const Text(
                      'Escalate Return Request to Storkia Admin',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Storkia Admin will review your evidence photos, order timeline, and the seller\'s rejection reason to make a final binding decision.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: StorkTheme.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Note to Storkia Admin (Optional)',
                        hintText:
                            'Add any extra context for the compliance review team...',
                        counterText: '',
                        fillColor: StorkTheme.surfaceSubtle,
                      ),
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        modalError!,
                        style: const TextStyle(
                          color: StorkTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StorkTheme.danger,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() {
                                  isSubmitting = true;
                                  modalError = null;
                                });
                                try {
                                  final Uri uri = returnRequestId != null &&
                                          returnRequestId > 0
                                      ? Uri.parse(
                                          '$_domain/api/v1/returns/$returnRequestId/escalate')
                                      : Uri.parse(
                                          '$_domain/api/v1/orders/${widget.orderId}/escalate-dispute');

                                  final response = await http
                                      .post(
                                        uri,
                                        headers: {
                                          'Authorization':
                                              'Bearer ${widget.token}',
                                          'Accept': 'application/json',
                                          'Content-Type': 'application/json',
                                        },
                                        body: json.encode({
                                          'escalation_note':
                                              noteCtrl.text.trim(),
                                        }),
                                      )
                                      .timeout(ApiConfig.requestTimeout);

                                  final data = json.decode(response.body);
                                  if (response.statusCode == 200 &&
                                      data is Map &&
                                      data['success'] == true) {
                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                    }
                                    _showSuccess(
                                      data['message']?.toString() ??
                                          'Request escalated to Storkia Admin.',
                                    );
                                    _fetchAllOrderData(silent: true);
                                  } else {
                                    setModalState(() {
                                      modalError = data is Map
                                          ? (data['message']?.toString() ??
                                              'Unable to escalate request.')
                                          : 'Unable to escalate request.';
                                    });
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError = 'Network error occurred.';
                                  });
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(() => isSubmitting = false);
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Submit Escalation to Admin'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _buyAgain() async {
    _showLoadingDialog();
    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/orders/${widget.orderId}/buy-again'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      Navigator.pop(context);

      final data = json.decode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        ref.read(cartCountProvider.notifier).fetchCartCount(widget.token);
        _showSuccess(
          data['message']?.toString() ?? 'Items added to your Shopping Cart!',
        );
        Navigator.push(
          context,
          StorkRoute.fade(
            CartScreen(baseUrl: _domain, token: widget.token),
          ),
        );
      } else {
        _showError(
          data is Map
              ? (data['message']?.toString() ??
                  'Items are currently out of stock.')
              : 'Items are currently out of stock.',
        );
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showError('Network error occurred.');
    }
  }

  void _showNetworkImagePreview(String title, String imageUrl,
      {bool requiresAuth = false}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: StorkTheme.surface,
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.62,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: InteractiveViewer(
                    child: Image.network(
                      imageUrl,
                      headers: requiresAuth
                          ? {'Authorization': 'Bearer ${widget.token}'}
                          : null,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Unable to load image preview.'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLoadingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: StorkTheme.primary),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: StorkTheme.success,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: StorkTheme.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _orderData == null) {
      return const Scaffold(
        backgroundColor: StorkTheme.surfaceSubtle,
        body: Center(
          child: CircularProgressIndicator(color: StorkTheme.primary),
        ),
      );
    }

    if (_orderData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Details')),
        body: const Center(child: Text('Order not found.')),
      );
    }

    final String status = _orderData!['status']?.toString() ?? 'pending';
    final String statusLabel = _orderData!['status_label']?.toString() ??
        status.replaceAll('_', ' ').toUpperCase();
    final String payMethod =
        _orderData!['effective_payment_method']?.toString() ?? 'COD';
    final String payStatus =
        _orderData!['payment_status']?.toString().toUpperCase() ?? 'UNPAID';
    final bool isRated = _orderData!['is_rated_by_buyer'] == true ||
        _orderData!['service_rating'] != null;
    final bool canCancelPreShipment =
        _orderData!['can_buyer_cancel_pre_shipment'] == true;
    final bool hasUnresolvedDispute =
        _orderData!['has_unresolved_dispute'] == true;
    final JsonMap? extra = _orderData!['extra'] is Map
        ? JsonMap.from(_orderData!['extra'] as Map)
        : null;
    final JsonMap? formattedReturn =
        _orderData!['formatted_return_request'] is Map
            ? JsonMap.from(_orderData!['formatted_return_request'] as Map)
            : (_orderData!['return_request'] is Map
                ? JsonMap.from(_orderData!['return_request'] as Map)
                : null);

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text(
          'Order #${_orderData!['seller_order_number'] ?? ''}',
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _openOrderInvoiceModal,
            tooltip: 'Order Invoice',
            icon: const Icon(Icons.receipt_long_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: StorkTheme.primary,
        onRefresh: () => _fetchAllOrderData(silent: true),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _buildStatusHeaderBanner(statusLabel, payMethod, payStatus),
            const SizedBox(height: 12),
            if (status == 'pending_buyer_response') ...[
              _buildPendingBuyerResponseBanner(),
              const SizedBox(height: 12),
            ],
            if (_liveTrackingData != null &&
                _liveTrackingData!['has_shipment'] == true) ...[
              _buildLiveTrackingAndRiderChatCard(),
              const SizedBox(height: 12),
            ],
            if (status == 'completed') ...[
              _buildCompletedBanner(isRated, extra),
              const SizedBox(height: 12),
            ],
            if (canCancelPreShipment) ...[
              _buildPreShipmentCancelBanner(),
              const SizedBox(height: 12),
            ],
            if (status == 'delivered' &&
                !hasUnresolvedDispute &&
                formattedReturn == null) ...[
              _buildDeliveredConfirmationBanner(),
              const SizedBox(height: 12),
            ],
            if (formattedReturn != null ||
                hasUnresolvedDispute ||
                status == 'disputed' ||
                status == 'returned_to_seller' ||
                extra?['seller_return_decision'] != null) ...[
              _buildDisputeStatusCard(extra, formattedReturn),
              const SizedBox(height: 12),
            ],
            _buildDeliveryAddressCard(),
            const SizedBox(height: 12),
            _buildShipmentAndPaymentInfoCard(payMethod, payStatus),
            const SizedBox(height: 12),
            _buildPurchasedItemsAndSummaryCard(payMethod, extra),
            const SizedBox(height: 12),
            _buildTrackingTimelineCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingBuyerResponseBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: StorkTheme.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTION REQUIRED: PAYMENT VERIFICATION NOTICE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your online payment submission was flagged. You can continue this order by switching to Cash on Delivery (COD) or cancel the order immediately to restore any vouchers and coins.',
            style: TextStyle(
              fontSize: 12.5,
              color: StorkTheme.textMain,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelFlaggedPaymentOrder,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: StorkTheme.danger,
                    side: const BorderSide(color: StorkTheme.danger),
                  ),
                  child: const Text('Cancel Order'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _switchFlaggedOrderToCod,
                  child: const Text('Switch to COD'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHeaderBanner(
      String statusLabel, String payMethod, String payStatus) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: StorkTheme.brandGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: StorkTheme.primaryDark.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${payMethod == 'WALLET' ? 'STORKIA E-WALLET' : payMethod} ($payStatus)',
                  style: const TextStyle(
                    color: StorkTheme.brandLight,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Parent: ${_orderData!['order'] is Map ? (_orderData!['order']['order_number'] ?? 'N/A') : 'N/A'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTrackingAndRiderChatCard() {
    final track = _liveTrackingData!;
    final JsonMap? driver =
        track['driver'] is Map ? JsonMap.from(track['driver'] as Map) : null;
    final bool isLive = track['is_live_active'] == true;
    final double? distMeters =
        double.tryParse(track['distance_meters']?.toString() ?? '');
    final int? etaMin = int.tryParse(track['eta_minutes']?.toString() ?? '');
    final String shipStatus = track['status']?.toString() ?? '';
    final bool canChatWithRider = driver != null &&
        driver['role']?.toString() == 'Rider' &&
        ['rider_assigned', 'out_for_delivery', 'delivery_failed']
            .contains(shipStatus);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive
              ? StorkTheme.success.withValues(alpha: 0.45)
              : StorkTheme.borderSubtle,
          width: isLive ? 1.5 : 1,
        ),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: isLive ? StorkTheme.success : StorkTheme.info,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isLive ? 'LIVE GPS TRACKING ACTIVE' : 'SHIPMENT ROUTE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color:
                          isLive ? StorkTheme.success : StorkTheme.primaryDark,
                    ),
                  ),
                ],
              ),
              if (etaMin != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: StorkTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'ETA ~$etaMin min${distMeters != null ? ' (${(distMeters / 1000).toStringAsFixed(1)} km)' : ''}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (driver != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StorkTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: StorkTheme.borderSubtle),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: StorkTheme.primary.withValues(alpha: 0.12),
                    child: Icon(
                      driver['role'] == 'Rider'
                          ? Icons.two_wheeler_rounded
                          : Icons.local_shipping_rounded,
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
                          '${driver['role']}: ${driver['name'] ?? 'Assigned Driver'}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.textMain,
                          ),
                        ),
                        Text(
                          '${driver['vehicle_type'] ?? 'Vehicle'} • Plate: ${driver['plate_number'] ?? 'N/A'}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                        if (driver['latitude'] != null &&
                            driver['longitude'] != null)
                          Text(
                            'GPS: ${double.tryParse(driver['latitude'].toString())?.toStringAsFixed(4)}, ${double.tryParse(driver['longitude'].toString())?.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: StorkTheme.primaryDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (canChatWithRider)
                    ElevatedButton.icon(
                      onPressed: _openDeliveryRiderChatSheet,
                      icon: const Icon(Icons.chat_rounded, size: 15),
                      label: Text(
                        _unreadDeliveryChatCount > 0
                            ? 'Chat ($_unreadDeliveryChatCount)'
                            : 'Chat Rider',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        minimumSize: const Size(0, 34),
                      ),
                    ),
                ],
              ),
            ),
          ] else
            Text(
              'Sorting Hub: ${track['sorting_hub']?['name'] ?? 'Partner Hub'} → ${track['destination']?['address'] ?? ''}',
              style: const TextStyle(
                fontSize: 12,
                color: StorkTheme.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompletedBanner(bool isRated, JsonMap? extra) {
    final JsonMap? serviceRating = _orderData!['service_rating'] is Map
        ? JsonMap.from(_orderData!['service_rating'] as Map)
        : null;
    final int coinsEarned =
        int.tryParse(extra?['coins_earned_on_completion']?.toString() ?? '0') ??
            0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRated
            ? StorkTheme.success.withValues(alpha: 0.08)
            : StorkTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isRated
              ? StorkTheme.success.withValues(alpha: 0.35)
              : StorkTheme.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isRated
                ? 'ORDER COMPLETED & RATED (${serviceRating?['overall_average_rating'] ?? '5.0'} ★)'
                : 'NEXT STEP: RATE YOUR ORDER (+UP TO 10 COINS PER ITEM)',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: isRated ? StorkTheme.success : const Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isRated
                ? 'Thank You for Rating This Order!'
                : 'Order Received! Rate Product, Condition, Seller, Logistics & Rider',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: StorkTheme.textMain,
            ),
          ),
          if (coinsEarned > 0) ...[
            const SizedBox(height: 4),
            Text(
              'You earned +$coinsEarned Storkia Coins completion cashback on this order!',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: StorkTheme.success,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: isRated
                ? ElevatedButton.icon(
                    onPressed: _buyAgain,
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const Text('Buy Again'),
                  )
                : ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        StorkRoute.fade(
                          LeaveReviewScreen(
                            sellerOrder: _orderData!,
                            baseUrl: _domain,
                            token: widget.token,
                          ),
                        ),
                      ).then((_) => _fetchAllOrderData(silent: true));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StorkTheme.warning,
                    ),
                    icon: const Icon(Icons.star_rounded, size: 18),
                    label: const Text('To Rate Order & Services'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreShipmentCancelBanner() {
    final int remaining = int.tryParse(
            _cancellationQuota['remaining_buyer']?.toString() ?? '5') ??
        5;
    final int limit =
        int.tryParse(_cancellationQuota['limit_by_buyer']?.toString() ?? '5') ??
            5;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need to cancel this order before shipment?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '7-day buyer cancellation quota remaining: $remaining of $limit',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: StorkTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _openPreShipmentCancelSheet,
            style: OutlinedButton.styleFrom(
              foregroundColor: StorkTheme.danger,
              side: const BorderSide(color: StorkTheme.danger),
            ),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveredConfirmationBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: StorkTheme.info.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Package Delivered — Confirm or Request Return',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.textMain,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isIdentityVerified
                      ? StorkTheme.success.withValues(alpha: 0.14)
                      : StorkTheme.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isIdentityVerified
                      ? 'Valid ID Verified ✓'
                      : 'Valid ID Required for Refund',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _isIdentityVerified
                        ? StorkTheme.success
                        : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Please inspect your items within 72 hours. Confirming receipt completes the order, awards Storkia Coins cashback, and unlocks 5-point ratings.',
            style: TextStyle(
              fontSize: 12,
              color: StorkTheme.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _openReturnRefundModal,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: StorkTheme.danger,
                    side: const BorderSide(color: StorkTheme.danger),
                  ),
                  child: const Text('Return / Refund'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _confirmReceipt,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StorkTheme.success,
                  ),
                  child: const Text('Order Received'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDisputeStatusCard(JsonMap? extra, JsonMap? formattedReturn) {
    final int? returnRequestId =
        int.tryParse(formattedReturn?['id']?.toString() ?? '');
    final String requestNo =
        formattedReturn?['request_number']?.toString() ?? '';
    final String statusText = formattedReturn?['status_label']?.toString() ??
        formattedReturn?['status']
            ?.toString()
            .replaceAll('_', ' ')
            .toUpperCase() ??
        (extra?['is_escalated_to_admin'] == true
            ? 'ESCALATED TO ADMIN'
            : (extra?['seller_return_decision'] != null
                ? 'SELLER: ${extra!['seller_return_decision'].toString().toUpperCase()}'
                : 'AWAITING SELLER REVIEW'));

    final String resolutionLabel =
        formattedReturn?['resolution_label']?.toString() ??
            formattedReturn?['requested_resolution']
                ?.toString()
                .replaceAll('_', ' ')
                .toUpperCase() ??
            'RETURN & REFUND';

    final String reasonCategory =
        formattedReturn?['reason_category_label']?.toString() ??
            formattedReturn?['reason_category']?.toString() ??
            extra?['dispute_reason_category']?.toString() ??
            '';
    final String reasonBody = formattedReturn?['reason']?.toString() ??
        _orderData!['dispute_reason']?.toString() ??
        '';

    final String? sellerDecision =
        formattedReturn?['seller_decision']?.toString() ??
            extra?['seller_return_decision']?.toString();
    final String? sellerReason =
        formattedReturn?['seller_decision_reason']?.toString() ??
            extra?['seller_return_decision_reason']?.toString();

    final bool isEscalated = formattedReturn?['is_escalated'] == true ||
        extra?['is_escalated_to_admin'] == true;
    final bool canEscalate = formattedReturn?['can_buyer_escalate'] == true ||
        (sellerDecision == 'rejected' && !isEscalated);

    final String? adminDecision =
        formattedReturn?['admin_decision']?.toString();
    final String? adminRemarks = formattedReturn?['admin_remarks']?.toString();

    final List<dynamic> evidencePhotos =
        formattedReturn != null && formattedReturn['evidence_photos'] is List
            ? List<dynamic>.from(formattedReturn['evidence_photos'] as List)
            : _extractList(extra?['dispute_evidence_photos']);

    final JsonMap? returnShipment = formattedReturn?['return_shipment'] is Map
        ? JsonMap.from(formattedReturn!['return_shipment'] as Map)
        : null;
    final List<dynamic> shipmentEvents =
        _extractList(returnShipment?['events']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.danger.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: StorkTheme.danger.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  requestNo.isNotEmpty
                      ? 'Return / Refund #$requestNo'
                      : 'Return / Refund Status',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.danger,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: StorkTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: StorkTheme.danger.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.danger,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Resolution: $resolutionLabel${reasonCategory.isNotEmpty ? ' • $reasonCategory' : ''}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: StorkTheme.primaryDark,
            ),
          ),
          if (reasonBody.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"$reasonBody"',
              style: const TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: StorkTheme.textMain,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Refund Amount: ₱${_formatMoney(formattedReturn?['refund_amount'] ?? extra?['refund_amount'] ?? _orderData!['total_amount'])} (${(formattedReturn?['refund_payout_method'] ?? extra?['refund_method'] ?? 'WALLET').toString() == 'WALLET' ? 'Instant Storkia E-Wallet' : 'GCash Refund'})',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          if (formattedReturn?['refund_reference'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Refund Reference #: ${formattedReturn!['refund_reference']}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: StorkTheme.success,
              ),
            ),
          ],
          if (evidencePhotos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in evidencePhotos)
                  Builder(builder: (context) {
                    final String rawUrl = p is Map
                        ? (p['url'] ?? p['path'] ?? '').toString()
                        : p.toString();
                    final url = ApiConfig.storageUrl(rawUrl, _domain);
                    return GestureDetector(
                      onTap: () => _showNetworkImagePreview(
                          'Return Evidence Photo', url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 54,
                            height: 54,
                            color: StorkTheme.surfaceSubtle,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ],
          if (returnShipment != null) ...[
            const Divider(height: 20),
            Text(
              'Return Shipment Tracking: #${returnShipment['tracking_number'] ?? 'N/A'} (${returnShipment['status_label'] ?? returnShipment['status'] ?? ''})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: StorkTheme.primaryDark,
              ),
            ),
            if (returnShipment['rider'] is Map) ...[
              const SizedBox(height: 4),
              Text(
                'Assigned Pickup Rider: ${returnShipment['rider']['name'] ?? returnShipment['rider']['full_name'] ?? 'Rider'} (${returnShipment['rider']['plate_number'] ?? ''})',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: StorkTheme.textMain,
                ),
              ),
            ],
            if (shipmentEvents.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final ev in shipmentEvents.take(3))
                if (ev is Map)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${ev['title'] ?? ''}: ${ev['description'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ),
            ],
          ],
          if (sellerDecision != null && sellerDecision.isNotEmpty) ...[
            const Divider(height: 20),
            Text(
              sellerDecision == 'rejected'
                  ? 'Seller Rejected Request: "${sellerReason ?? 'Declined'}"'
                  : 'Seller Response: ${sellerDecision.replaceAll('_', ' ').toUpperCase()}${sellerReason != null && sellerReason.isNotEmpty ? ' — "$sellerReason"' : ''}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sellerDecision == 'rejected'
                    ? StorkTheme.danger
                    : StorkTheme.success,
              ),
            ),
          ],
          if (adminDecision != null && adminDecision.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Storkia Admin Final Decision (${adminDecision.replaceAll('_', ' ').toUpperCase()}): "${adminRemarks ?? ''}"',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: StorkTheme.primaryDark,
              ),
            ),
          ],
          if (canEscalate) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: StorkTheme.danger,
                ),
                onPressed: () => _openEscalateReturnDialog(returnRequestId),
                child: const Text('Escalate to Storkia Admin'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryAddressCard() {
    final JsonMap address = _orderData!['delivery_address_snapshot'] is Map
        ? JsonMap.from(_orderData!['delivery_address_snapshot'] as Map)
        : <String, dynamic>{};

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
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: StorkTheme.primary,
              ),
              SizedBox(width: 6),
              Text(
                'DELIVERY ADDRESS SNAPSHOT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: StorkTheme.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${address['recipient_name'] ?? 'Recipient'}  •  ${address['phone_number'] ?? ''}',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: StorkTheme.textMain,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            address['full_address']?.toString() ?? 'No address provided',
            style: const TextStyle(
              fontSize: 12.5,
              color: StorkTheme.textMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShipmentAndPaymentInfoCard(String payMethod, String payStatus) {
    final JsonMap? shipment = _orderData!['shipment'] is Map
        ? JsonMap.from(_orderData!['shipment'] as Map)
        : null;
    final List<dynamic> packages = _extractList(shipment?['packages']);
    final List<dynamic> proofs = _extractList(shipment?['delivery_proofs']);
    final JsonMap? latestProof = proofs.isNotEmpty && proofs.first is Map
        ? JsonMap.from(proofs.first as Map)
        : null;

    final String pkgRefs = [
      for (final p in packages)
        if (p is Map &&
            (p['package_reference']?.toString().isNotEmpty ?? false))
          p['package_reference'].toString(),
    ].join(', ');

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
            'SHIPMENT & PAYMENT INFO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            'Seller Store:',
            (_orderData!['seller_profile'] is Map
                    ? _orderData!['seller_profile']['business_name']?.toString()
                    : null) ??
                'N/A',
          ),
          _buildInfoRow(
            'Logistics Provider:',
            (_orderData!['logistics_profile'] is Map
                    ? _orderData!['logistics_profile']['business_name']
                        ?.toString()
                    : null) ??
                'Awaiting Seller Selection',
          ),
          _buildInfoRow(
            'Tracking Number:',
            shipment?['tracking_number']?.toString() ?? 'Not generated yet',
          ),
          if (pkgRefs.isNotEmpty)
            _buildInfoRow('Package Reference(s):', pkgRefs),
          _buildInfoRow(
            'Payment Method:',
            '${payMethod == 'WALLET' ? 'Storkia E-Wallet' : payMethod} ($payStatus)',
          ),
          const Divider(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openOrderInvoiceModal,
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('View Order Invoice'),
              ),
              if (latestProof != null && latestProof['id'] != null)
                OutlinedButton.icon(
                  onPressed: () => _showNetworkImagePreview(
                    'Proof of Delivery',
                    '$_domain/api/v1/orders/proof/${latestProof['id']}',
                    requiresAuth: true,
                  ),
                  icon: const Icon(Icons.photo_camera_back_rounded, size: 16),
                  label: const Text('Inspect Delivery Photo'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: StorkTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: StorkTheme.textMain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchasedItemsAndSummaryCard(String payMethod, JsonMap? extra) {
    final List<dynamic> items = _extractList(_orderData!['items']);
    final double storeDisc =
        double.tryParse(extra?['store_voucher_discount']?.toString() ?? '0') ??
            0.0;
    final double platDisc = double.tryParse(
            extra?['platform_voucher_discount']?.toString() ?? '0') ??
        0.0;
    final double shipDisc = double.tryParse(
            extra?['shipping_voucher_discount']?.toString() ?? '0') ??
        0.0;
    final double origShipFee =
        double.tryParse(extra?['original_shipping_fee']?.toString() ?? '0') ??
            0.0;
    final int coinsUsed =
        int.tryParse(extra?['coins_used']?.toString() ?? '0') ?? 0;
    final double coinsDisc =
        double.tryParse(extra?['coins_discount_amount']?.toString() ?? '0') ??
            0.0;

    return Container(
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
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: StorkTheme.surfaceSubtle.withValues(alpha: 0.7),
            child: const Text(
              'Purchased Items',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: StorkTheme.primaryDark,
              ),
            ),
          ),
          for (final rawItem in items)
            if (rawItem is Map)
              Padding(
                padding: const EdgeInsets.all(14),
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
                      child: rawItem['product_image'] != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.network(
                                ApiConfig.storageUrl(
                                    rawItem['product_image'].toString(),
                                    _domain),
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
                            rawItem['product_name']?.toString() ?? '',
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
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                          Text(
                            '₱${_formatMoney(rawItem['discounted_unit_price'])} × ${rawItem['quantity']}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${_formatMoney(rawItem['line_total'])}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.textMain,
                      ),
                    ),
                  ],
                ),
              ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (storeDisc > 0)
                  _buildInfoRow(
                    'Store / Bundle Discount:',
                    '-₱${_formatMoney(storeDisc)}',
                  ),
                if (platDisc > 0)
                  _buildInfoRow(
                    'Platform Voucher (${extra?['platform_voucher_code'] ?? ''}):',
                    '-₱${_formatMoney(platDisc)}',
                  ),
                if (coinsDisc > 0)
                  _buildInfoRow(
                    'Storkia Coins ($coinsUsed Coins):',
                    '-₱${_formatMoney(coinsDisc)}',
                  ),
                _buildInfoRow(
                  'Net Product Subtotal:',
                  '₱${_formatMoney(_orderData!['subtotal_amount'])}',
                ),
                if (shipDisc > 0 && origShipFee > 0)
                  _buildInfoRow(
                    'Original Shipping Fee (${_orderData!['total_weight'] ?? '0'} kg):',
                    '₱${_formatMoney(origShipFee)}',
                  ),
                if (shipDisc > 0)
                  _buildInfoRow(
                    'Shipping Voucher (${extra?['shipping_voucher_code'] ?? 'FREE SHIP'}):',
                    '-₱${_formatMoney(shipDisc)}',
                  ),
                _buildInfoRow(
                  'Net Shipping Fee (${_orderData!['total_weight'] ?? '0'} kg):',
                  '₱${_formatMoney(_orderData!['shipping_fee'])}',
                ),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Total Order Amount (${payMethod == 'WALLET' ? 'E-Wallet' : payMethod}):',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${_formatMoney(_orderData!['total_amount'])}',
                      style: const TextStyle(
                        fontSize: 18,
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

  Widget _buildTrackingTimelineCard() {
    final List<dynamic> histories =
        _extractList(_orderData!['status_histories']);

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
            children: [
              Icon(
                Icons.local_shipping_outlined,
                color: StorkTheme.primary,
                size: 19,
              ),
              SizedBox(width: 8),
              Text(
                'Order & Shipment Timeline',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: StorkTheme.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (histories.isEmpty)
            const Text(
              'No status logs recorded yet.',
              style: TextStyle(fontSize: 12.5, color: StorkTheme.textMuted),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: histories.length,
              itemBuilder: (context, index) {
                final rawHistory = histories[index];
                if (rawHistory is! Map) return const SizedBox.shrink();
                final history = JsonMap.from(rawHistory);
                final bool isLatest = index == 0;
                final String statusTitle = (history['to_status'] ?? '')
                    .toString()
                    .replaceAll('_', ' ')
                    .toUpperCase();
                final String remarks = history['remarks']?.toString() ?? '';
                final String createdAt =
                    history['created_at']?.toString() ?? '';

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLatest
                                ? StorkTheme.primary
                                : StorkTheme.borderSubtle,
                          ),
                        ),
                        if (index != histories.length - 1)
                          Container(
                            width: 2,
                            height: 44,
                            color: StorkTheme.borderSubtle,
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusTitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isLatest
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isLatest
                                    ? StorkTheme.primaryDark
                                    : StorkTheme.textMuted,
                              ),
                            ),
                            if (remarks.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                remarks,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: StorkTheme.textMuted,
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              createdAt,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DeliveryRiderChatBottomSheet extends StatefulWidget {
  final int orderId;
  final String domain;
  final String token;

  const _DeliveryRiderChatBottomSheet({
    required this.orderId,
    required this.domain,
    required this.token,
  });

  @override
  State<_DeliveryRiderChatBottomSheet> createState() =>
      _DeliveryRiderChatBottomSheetState();
}

class _DeliveryRiderChatBottomSheetState
    extends State<_DeliveryRiderChatBottomSheet> {
  final TextEditingController _msgCtrl = TextEditingController();
  Timer? _pollTimer;
  bool _isLoading = true;
  bool _isSending = false;
  bool _canSend = false;
  JsonMap? _rider;
  List<JsonMap> _messages = [];

  @override
  void initState() {
    super.initState();
    _fetchChat();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchChat(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchChat({bool silent = false}) async {
    try {
      final response = await http.get(
        Uri.parse(
            '${widget.domain}/api/v1/orders/${widget.orderId}/delivery-chat'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted || response.statusCode != 200) return;
      final body = json.decode(response.body);
      if (body is Map && body['success'] == true) {
        final List<dynamic> rawMsgs = body['messages'] is List
            ? List<dynamic>.from(body['messages'] as List)
            : <dynamic>[];
        setState(() {
          _canSend = body['can_send'] == true;
          _rider =
              body['rider'] is Map ? JsonMap.from(body['rider'] as Map) : null;
          _messages = [
            for (final m in rawMsgs)
              if (m is Map) JsonMap.from(m),
          ];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending || !_canSend) return;
    setState(() => _isSending = true);
    _msgCtrl.clear();

    try {
      final response = await http
          .post(
            Uri.parse(
                '${widget.domain}/api/v1/orders/${widget.orderId}/delivery-chat'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({'message': text}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        _fetchChat(silent: true);
      } else {
        _msgCtrl.text = text;
      }
    } catch (_) {
      _msgCtrl.text = text;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: Column(
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: StorkTheme.borderSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.two_wheeler_rounded,
                    color: StorkTheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _rider != null
                              ? 'Delivery Chat: ${_rider!['name'] ?? 'Rider'}'
                              : 'Buyer-Rider Delivery Chat',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        if (_rider != null)
                          Text(
                            '${_rider!['vehicle_type'] ?? ''} • Plate: ${_rider!['plate_number'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: StorkTheme.primary),
                    )
                  : _messages.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Send a doorstep landmark or delivery note to your assigned Rider.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final m = _messages[index];
                            final bool isBuyer =
                                m['sender_type']?.toString() == 'buyer';
                            return Align(
                              alignment: isBuyer
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * 0.72,
                                ),
                                decoration: BoxDecoration(
                                  gradient:
                                      isBuyer ? StorkTheme.brandGradient : null,
                                  color:
                                      isBuyer ? null : StorkTheme.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  m['message']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isBuyer
                                        ? Colors.white
                                        : StorkTheme.textMain,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: StorkTheme.surface,
                border: Border(top: BorderSide(color: StorkTheme.borderSubtle)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgCtrl,
                        enabled: _canSend,
                        decoration: InputDecoration(
                          hintText: _canSend
                              ? 'Message your delivery rider...'
                              : 'Chat active only during active rider delivery',
                          fillColor: StorkTheme.surfaceSubtle,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed:
                          (_canSend && !_isSending) ? _sendMessage : null,
                      icon: const Icon(
                        Icons.send_rounded,
                        color: StorkTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
