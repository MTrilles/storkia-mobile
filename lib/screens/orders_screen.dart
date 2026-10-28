import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/order_model.dart';
import 'order_details_screen.dart'; // Uncommented import

class OrdersScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const OrdersScreen({super.key, required this.baseUrl, required this.token});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = [
    'all',
    'unpaid',
    'processing',
    'shipped',
    'review',
    'returns'
  ];
  final List<String> _tabLabels = [
    'All',
    'Unpaid',
    'Processing',
    'Shipped',
    'To Review',
    'Returns'
  ];

  final Map<String, List<SellerOrder>> _orders = {};
  final Map<String, bool> _isLoading = {};
  final Map<String, int> _currentPage = {};
  final Map<String, bool> _hasMore = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);

    for (var tab in _tabs) {
      _orders[tab] = [];
      _isLoading[tab] = false;
      _currentPage[tab] = 1;
      _hasMore[tab] = true;
    }

    _fetchOrders(_tabs[0]);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final currentTab = _tabs[_tabController.index];
        if (_orders[currentTab]!.isEmpty && _hasMore[currentTab]!) {
          _fetchOrders(currentTab);
        }
      }
    });
  }

  Future<void> _fetchOrders(String tab, {bool loadMore = false}) async {
    if (_isLoading[tab]! || (!_hasMore[tab]! && loadMore)) return;

    setState(() => _isLoading[tab] = true);

    try {
      final page = loadMore ? _currentPage[tab]! + 1 : 1;
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/v1/orders?status=$tab&page=$page'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paginatedData = data['data'];
        final List newOrdersJson = paginatedData['data'];

        final newOrders =
            newOrdersJson.map((json) => SellerOrder.fromJson(json)).toList();

        setState(() {
          if (loadMore) {
            _orders[tab]!.addAll(newOrders);
            _currentPage[tab] = page;
          } else {
            _orders[tab] = newOrders;
            _currentPage[tab] = 1;
          }
          _hasMore[tab] = _currentPage[tab]! < paginatedData['last_page'];
        });
      }
    } catch (e) {
      // Handle error quietly
    } finally {
      if (mounted) setState(() => _isLoading[tab] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF292524),
        title: const Text('My Orders',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFFCF4173),
          unselectedLabelColor: const Color(0xFF78716C),
          indicatorColor: const Color(0xFFCF4173),
          tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) => _buildOrderList(tab)).toList(),
      ),
    );
  }

  Widget _buildOrderList(String tab) {
    if (_isLoading[tab]! && _orders[tab]!.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFCF4173)));
    }

    if (_orders[tab]!.isEmpty) {
      return const Center(
          child: Text('No orders found.',
              style: TextStyle(color: Color(0xFF78716C))));
    }

    return RefreshIndicator(
      color: const Color(0xFFCF4173),
      onRefresh: () => _fetchOrders(tab),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _orders[tab]!.length + (_hasMore[tab]! ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _orders[tab]!.length) {
            _fetchOrders(tab, loadMore: true);
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child:
                        CircularProgressIndicator(color: Color(0xFFCF4173))));
          }

          final order = _orders[tab]![index];
          return _buildOrderCard(order);
        },
      ),
    );
  }

  Widget _buildOrderCard(SellerOrder order) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailsScreen(
              orderId: order.id,
              baseUrl: widget.baseUrl,
              token: widget.token,
            ),
          ),
        );
      },
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storefront,
                          size: 16, color: Color(0xFF78716C)),
                      const SizedBox(width: 8),
                      Text(order.businessName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  Text(order.readableStatus,
                      style: const TextStyle(
                          color: Color(0xFFCF4173),
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(height: 1),
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item.productImage != null
                              ? Image.network(
                                  '${widget.baseUrl}/storage/${item.productImage}',
                                  fit: BoxFit.cover)
                              : const Icon(Icons.image, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                            if (item.variantName != null)
                              Text('${item.variantName}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF78716C))),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    '₱${item.discountedUnitPrice.toStringAsFixed(2)}'),
                                Text('x${item.quantity}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF78716C))),
                              ],
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                )),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${order.items.length} items',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF78716C))),
                  Row(
                    children: [
                      const Text('Order Total: ',
                          style: TextStyle(fontSize: 13)),
                      Text('₱${order.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Color(0xFFCF4173),
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
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
}
