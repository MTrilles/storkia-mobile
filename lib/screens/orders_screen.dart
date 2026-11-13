import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../providers/global_counters_provider.dart';
import 'cart_screen.dart';
import 'leave_review_screen.dart';
import 'order_details_screen.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef TabOrdersCache = Map<String, JsonList>;
typedef StringMap = Map<String, String>;
typedef StringIntMap = Map<String, int>;

class OrdersScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;
  final String initialTab;

  const OrdersScreen({
    super.key,
    required this.baseUrl,
    required this.token,
    this.initialTab = 'all',
  });

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;
  Timer? _autoSyncTimer;

  static const List<StringMap> _tabs = [
    {'key': 'all', 'label': 'All'},
    {'key': 'unpaid', 'label': 'Unpaid / Action'},
    {'key': 'processing', 'label': 'Processing'},
    {'key': 'shipped', 'label': 'Shipped'},
    {'key': 'to_confirm', 'label': 'To Confirm'},
    {'key': 'to_rate', 'label': 'To Rate'},
    {'key': 'completed', 'label': 'Completed'},
    {'key': 'returns', 'label': 'Cancelled / Disputed'},
  ];

  bool _isLoading = true;
  bool _isFetchingMore = false;
  JsonList _orders = [];
  final TabOrdersCache _ordersCacheByTab = {};
  StringIntMap _counts = {};
  int _currentPage = 1;
  bool _hasMore = false;
  String _activeTabKey = 'all';
  String _searchQuery = '';

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeTabKey = widget.initialTab;
    int initialIndex =
        _tabs.indexWhere((tab) => tab['key'] == widget.initialTab);
    if (initialIndex == -1) initialIndex = 0;

    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _fetchOrders(silent: false);

    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_isLoading && !_isFetchingMore) {
        _fetchOrders(isRefresh: true, silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchOrders(isRefresh: true, silent: true);
    }
  }

  List<dynamic> _extractList(dynamic value) {
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[];
  }

  bool _isTerminalStatus(String status) {
    return const [
      'completed',
      'cancelled',
      'rejected',
      'returned_to_seller',
    ].contains(status.toLowerCase());
  }

  JsonList _sortActiveFirst(JsonList list) {
    final active = <JsonMap>[];
    final terminal = <JsonMap>[];
    for (final o in list) {
      final s = (o['status'] ?? '').toString();
      if (_isTerminalStatus(s)) {
        terminal.add(o);
      } else {
        active.add(o);
      }
    }
    return [...active, ...terminal];
  }

  bool _matchesTabKey(JsonMap order, String tabKey) {
    if (tabKey == 'all') return true;
    final String status = (order['status'] ?? '').toString().toLowerCase();
    final String payStatus =
        (order['payment_status'] ?? '').toString().toLowerCase();
    final bool isRated =
        order['is_rated_by_buyer'] == true || order['service_rating'] != null;

    switch (tabKey) {
      case 'unpaid':
        return ['unpaid', 'flagged'].contains(payStatus) &&
            !['cancelled', 'rejected', 'returned_to_seller'].contains(status);
      case 'processing':
        return [
          'pending_seller_acceptance',
          'pending_buyer_response',
          'accepted',
          'preparing',
          'ready_for_pickup',
          'pickup_assigned',
        ].contains(status);
      case 'shipped':
        return [
          'picked_up',
          'at_logistics_hub',
          'out_for_delivery',
          'delivery_failed',
        ].contains(status);
      case 'to_confirm':
        return status == 'delivered' && order['has_unresolved_dispute'] != true;
      case 'to_rate':
        return status == 'completed' && !isRated;
      case 'completed':
        return status == 'completed' && isRated;
      case 'returns':
        return [
              'cancelled',
              'rejected',
              'returned_to_seller',
              'disputed',
            ].contains(status) ||
            order['has_unresolved_dispute'] == true;
      default:
        return true;
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 220) {
      if (!_isFetchingMore && _hasMore && !_isLoading) {
        _fetchOrders(loadMore: true, silent: true);
      }
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final selectedKey = _tabs[_tabController.index]['key']!;
    if (selectedKey == _activeTabKey) return;

    final cachedForTab = _ordersCacheByTab[selectedKey];
    final allCached = _ordersCacheByTab['all'];

    setState(() {
      _activeTabKey = selectedKey;
      _currentPage = 1;
      _hasMore = false;
      if (cachedForTab != null) {
        _orders = JsonList.from(cachedForTab);
      } else if (allCached != null && _searchQuery.isEmpty) {
        _orders = _sortActiveFirst(
          allCached.where((o) => _matchesTabKey(o, selectedKey)).toList(),
        );
      }
    });
    _fetchOrders(silent: true);
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 320), () {
      setState(() {
        _searchQuery = query.trim();
        _currentPage = 1;
        _hasMore = false;
      });
      _fetchOrders(silent: true);
    });
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

  Future<void> _fetchOrders({
    bool isRefresh = false,
    bool loadMore = false,
    bool silent = true,
  }) async {
    final String requestedTab = _activeTabKey;
    if (loadMore) {
      setState(() => _isFetchingMore = true);
    } else if (!isRefresh && !silent && _orders.isEmpty) {
      setState(() => _isLoading = true);
    }

    final int targetPage = loadMore ? _currentPage + 1 : 1;

    try {
      final Uri uri = Uri.parse('$_domain/api/v1/orders').replace(
        queryParameters: {
          'status': requestedTab,
          if (_searchQuery.isNotEmpty) 'search': _searchQuery,
          'page': '$targetPage',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted || requestedTab != _activeTabKey) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['success'] == true && data['data'] is Map) {
          final paginatedData = Map<String, dynamic>.from(data['data'] as Map);
          final List<dynamic> rawList = _extractList(paginatedData['data']);
          final JsonList parsedOrders = [
            for (final e in rawList)
              if (e is Map) Map<String, dynamic>.from(e),
          ];

          final StringIntMap parsedCounts = {};
          if (data['counts'] is Map) {
            (data['counts'] as Map).forEach((k, v) {
              parsedCounts[k.toString()] = int.tryParse(v.toString()) ?? 0;
            });
            ref
                .read(orderCountsProvider.notifier)
                .updateFromMap(data['counts'] as Map);
          }

          final int current =
              int.tryParse(paginatedData['current_page']?.toString() ?? '1') ??
                  1;
          final int last =
              int.tryParse(paginatedData['last_page']?.toString() ?? '1') ?? 1;

          setState(() {
            if (loadMore) {
              final existingIds = _orders
                  .map((o) => int.tryParse(o['id']?.toString() ?? '0') ?? 0)
                  .toSet();
              for (final item in parsedOrders) {
                final id = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
                if (!existingIds.contains(id)) {
                  _orders.add(item);
                }
              }
              _orders = _sortActiveFirst(_orders);
              _currentPage = current;
              _hasMore = current < last;
            } else {
              _orders = _sortActiveFirst(parsedOrders);
              _currentPage = current;
              _hasMore = current < last;
            }
            if (_searchQuery.isEmpty) {
              _ordersCacheByTab[requestedTab] = JsonList.from(_orders);
            }
            if (parsedCounts.isNotEmpty) {
              _counts = parsedCounts;
            }
            _isLoading = false;
            _isFetchingMore = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isFetchingMore = false;
      });
    }
  }

  Future<void> _confirmReceipt(int orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Confirm Order Received',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: const Text(
          'Have you inspected and received all items in good condition? Confirming completes the order, awards Storkia Coins cashback, and unlocks rating.',
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
            child: const Text('Order Received'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/orders/$orderId/confirm-receipt'),
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
        syncAllBuyerCounters(ref, widget.token);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ??
                  'Order confirmed! You can now rate this order.',
            ),
            backgroundColor: StorkTheme.success,
          ),
        );
        _fetchOrders(isRefresh: true, silent: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data is Map
                  ? (data['message']?.toString() ??
                      'Unable to confirm receipt.')
                  : 'Unable to confirm receipt.',
            ),
            backgroundColor: StorkTheme.danger,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _buyAgain(int orderId) async {
    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/orders/$orderId/buy-again'),
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
        ref.read(cartCountProvider.notifier).fetchCartCount(widget.token);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ?? 'Items added to your cart!',
            ),
            backgroundColor: StorkTheme.success,
          ),
        );
        Navigator.push(
          context,
          StorkRoute.fade(
            CartScreen(baseUrl: _domain, token: widget.token),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data is Map
                  ? (data['message']?.toString() ??
                      'Items are currently out of stock.')
                  : 'Items are currently out of stock.',
            ),
            backgroundColor: StorkTheme.danger,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final globalOrderCounts = ref.watch(orderCountsProvider);

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('My Orders'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(106),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search Order #, store, or product...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: StorkTheme.primary,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: StorkTheme.surfaceSubtle,
                  ),
                ),
              ),
              TabBar(
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
                tabs: _tabs.map((tab) {
                  final key = tab['key']!;
                  final count = _counts.containsKey(key)
                      ? (_counts[key] ?? 0)
                      : globalOrderCounts.countForTab(key);
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tab['label']!),
                        if (count > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: key == 'to_rate'
                                  ? StorkTheme.warning.withValues(alpha: 0.2)
                                  : StorkTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: key == 'to_rate'
                                    ? const Color(0xFF92400E)
                                    : StorkTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading && _orders.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchOrders(isRefresh: true, silent: true),
              child: _orders.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Container(
                            width: 74,
                            height: 74,
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
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No Orders Found in This Section',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Active orders appear at the top; completed and cancelled orders move to the bottom.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: StorkTheme.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(14),
                      itemCount: _orders.length + (_isFetchingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index >= _orders.length) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: StorkTheme.primary,
                              ),
                            ),
                          );
                        }
                        return _buildOrderCard(_orders[index]);
                      },
                    ),
            ),
    );
  }

  Widget _buildOrderCard(JsonMap sellerOrder) {
    final seller = sellerOrder['seller_profile'] is Map
        ? Map<String, dynamic>.from(sellerOrder['seller_profile'] as Map)
        : <String, dynamic>{};
    final List<dynamic> items = _extractList(sellerOrder['items']);
    final String status = sellerOrder['status']?.toString() ?? 'pending';
    final String statusLabel = sellerOrder['status_label']?.toString() ??
        status.replaceAll('_', ' ').toUpperCase();
    final String payMethod =
        sellerOrder['effective_payment_method']?.toString() ??
            (sellerOrder['payment'] is Map
                ? sellerOrder['payment']['method']?.toString()
                : null) ??
            'COD';
    final String paymentStatus =
        sellerOrder['payment_status']?.toString().toUpperCase() ?? 'UNPAID';
    final int orderId = int.tryParse(sellerOrder['id']?.toString() ?? '0') ?? 0;
    final bool isRated = sellerOrder['is_rated_by_buyer'] == true ||
        sellerOrder['service_rating'] != null;
    final bool hasUnresolvedDispute =
        sellerOrder['has_unresolved_dispute'] == true;
    final JsonMap? shipment = sellerOrder['shipment'] is Map
        ? Map<String, dynamic>.from(sellerOrder['shipment'] as Map)
        : null;
    final JsonMap? extra = sellerOrder['extra'] is Map
        ? Map<String, dynamic>.from(sellerOrder['extra'] as Map)
        : null;
    final JsonMap? serviceRating = sellerOrder['service_rating'] is Map
        ? Map<String, dynamic>.from(sellerOrder['service_rating'] as Map)
        : null;
    final int coinsUsed =
        int.tryParse(extra?['coins_used']?.toString() ?? '0') ?? 0;
    final double coinsDiscount =
        double.tryParse(extra?['coins_discount_amount']?.toString() ?? '0') ??
            0.0;
    final int coinsEarned =
        int.tryParse(extra?['coins_earned_on_completion']?.toString() ?? '0') ??
            0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          StorkRoute.fade(
            OrderDetailsScreen(
              orderId: orderId,
              baseUrl: _domain,
              token: widget.token,
            ),
          ),
        ).then((_) {
          syncAllBuyerCounters(ref, widget.token);
          _fetchOrders(isRefresh: true, silent: true);
        });
      },
      child: Container(
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
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        const Icon(
                          Icons.storefront_rounded,
                          size: 16,
                          color: StorkTheme.primaryDark,
                        ),
                        Text(
                          seller['business_name']?.toString() ?? 'Seller Store',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: StorkTheme.brandLight.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '#${sellerOrder['seller_order_number'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: payMethod == 'WALLET'
                                ? StorkTheme.primaryDark.withValues(alpha: 0.1)
                                : StorkTheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: StorkTheme.borderSubtle),
                          ),
                          child: Text(
                            payMethod == 'WALLET' ? 'E-WALLET' : payMethod,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: payMethod == 'WALLET'
                                  ? StorkTheme.primaryDark
                                  : StorkTheme.textMain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(status, statusLabel, isRated),
                ],
              ),
            ),
            if (status == 'pending_seller_acceptance')
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: StorkTheme.info.withValues(alpha: 0.08),
                child: const Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 15, color: StorkTheme.info),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '24h Seller Acceptance Protection: Auto-refunds & awards +50 Storkia Coins if unaccepted in 24h.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: StorkTheme.textMain,
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
                            const SizedBox(height: 2),
                            Text(
                              'Qty: ${rawItem['quantity']} • ₱${_formatMoney(rawItem['discounted_unit_price'])}',
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
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.textMain,
                        ),
                      ),
                    ],
                  ),
                ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.all(14),
              color: StorkTheme.surfaceSubtle.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '${payMethod == 'WALLET' ? 'E-Wallet' : payMethod} ($paymentStatus)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total: ₱${_formatMoney(sellerOrder['total_amount'])}',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: StorkTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  if (coinsUsed > 0 || coinsEarned > 0) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (coinsUsed > 0)
                          Text(
                            'Redeemed $coinsUsed Coins (-₱${_formatMoney(coinsDiscount)})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        if (coinsEarned > 0)
                          Text(
                            'Earned +$coinsEarned Cashback Coins',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.success,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (shipment != null &&
                      shipment['tracking_number'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Tracking #: ${shipment['tracking_number']}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                  ],
                  if (serviceRating != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Your Rating: ${serviceRating['overall_average_rating'] ?? '5.0'} / 5.0 ★',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      if (status == 'delivered' && !hasUnresolvedDispute)
                        ElevatedButton(
                          onPressed: () => _confirmReceipt(orderId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: StorkTheme.success,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text(
                            'Order Received',
                            style: TextStyle(fontSize: 12),
                          ),
                        )
                      else if (status == 'completed' && !isRated)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              StorkRoute.fade(
                                LeaveReviewScreen(
                                  sellerOrder: sellerOrder,
                                  baseUrl: _domain,
                                  token: widget.token,
                                ),
                              ),
                            ).then((_) {
                              syncAllBuyerCounters(ref, widget.token);
                              _fetchOrders(isRefresh: true, silent: true);
                            });
                          },
                          icon: const Icon(Icons.star_rounded, size: 16),
                          label: const Text(
                            'Rate (+Up to 10 Coins)',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: StorkTheme.warning,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                        )
                      else if (status == 'completed' && isRated)
                        ElevatedButton(
                          onPressed: () => _buyAgain(orderId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: StorkTheme.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text(
                            'Buy Again',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            StorkRoute.fade(
                              OrderDetailsScreen(
                                orderId: orderId,
                                baseUrl: _domain,
                                token: widget.token,
                              ),
                            ),
                          ).then((_) {
                            syncAllBuyerCounters(ref, widget.token);
                            _fetchOrders(isRefresh: true, silent: true);
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: StorkTheme.primaryDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text(
                          'Track & Details',
                          style: TextStyle(fontSize: 12),
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
    );
  }

  Widget _buildStatusBadge(String status, String label, bool isRated) {
    Color bgColor = StorkTheme.warning.withValues(alpha: 0.14);
    Color textColor = const Color(0xFF92400E);

    if (status == 'completed') {
      bgColor = isRated
          ? StorkTheme.success.withValues(alpha: 0.14)
          : StorkTheme.warning.withValues(alpha: 0.18);
      textColor = isRated ? StorkTheme.success : const Color(0xFF92400E);
    } else if (status == 'delivered') {
      bgColor = StorkTheme.info.withValues(alpha: 0.14);
      textColor = StorkTheme.info;
    } else if (status == 'out_for_delivery' ||
        status == 'picked_up' ||
        status == 'at_logistics_hub') {
      bgColor = const Color(0xFF4F46E5).withValues(alpha: 0.12);
      textColor = const Color(0xFF4338CA);
    } else if (status == 'rejected' ||
        status == 'cancelled' ||
        status == 'returned_to_seller' ||
        status == 'disputed' ||
        status == 'delivery_failed') {
      bgColor = StorkTheme.danger.withValues(alpha: 0.12);
      textColor = StorkTheme.danger;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
