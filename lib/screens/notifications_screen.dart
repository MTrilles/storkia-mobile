import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../providers/global_counters_provider.dart';
import 'order_details_screen.dart';
import 'points_rewards_screen.dart';

typedef JsonMap = Map<String, dynamic>;

class NotificationsScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;

  const NotificationsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  List<JsonMap> _notifications = [];
  Timer? _autoSyncTimer;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchNotifications();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _fetchNotifications(silent: true);
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
      _fetchNotifications(silent: true);
    }
  }

  JsonMap _extractPayload(JsonMap item) {
    final JsonMap merged = JsonMap.from(item);
    dynamic rawData = item['data'];

    if (rawData is String && rawData.trim().isNotEmpty) {
      try {
        rawData = json.decode(rawData);
        if (rawData is String && rawData.trim().isNotEmpty) {
          rawData = json.decode(rawData);
        }
      } catch (_) {}
    }

    if (rawData is Map) {
      rawData.forEach((k, v) {
        merged[k.toString()] = v;
      });
    }

    return merged;
  }

  String _resolveTitle(JsonMap payload) {
    for (final key in ['title', 'subject', 'heading', 'status_label']) {
      final val = payload[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    if (payload['seller_order_number'] != null) {
      return 'Order #${payload['seller_order_number']} Update';
    }
    return 'Order Update';
  }

  String _resolveMessage(JsonMap payload) {
    for (final key in [
      'message',
      'body',
      'description',
      'remarks',
      'content',
      'text',
      'summary',
    ]) {
      final val = payload[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    final orderNo =
        payload['seller_order_number'] ?? payload['order_number'] ?? '';
    final status = payload['status']?.toString().replaceAll('_', ' ') ?? '';
    if (orderNo.toString().isNotEmpty && status.isNotEmpty) {
      return 'Order #$orderNo status updated to ${status.toUpperCase()}. Tap to view order details.';
    }
    return 'Tap to view full details.';
  }

  String _formatTimestamp(JsonMap item, JsonMap payload) {
    final human = (item['created_at_human'] ?? payload['created_at_human'])
        ?.toString()
        .trim();
    final raw = (item['created_at'] ?? payload['created_at'])?.toString() ?? '';
    if (raw.isEmpty) return human ?? '';

    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return human ?? raw;

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final formatted =
        '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $hour12:$min $amPm';

    final diff = DateTime.now().difference(dt);
    String rel = '';
    if (diff.inSeconds < 60) {
      rel = 'Just now';
    } else if (diff.inMinutes < 60) {
      rel = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      rel = '${diff.inHours}h ago';
    } else if (diff.inDays < 30) {
      rel = '${diff.inDays}d ago';
    }

    return rel.isNotEmpty ? '$formatted ($rel)' : formatted;
  }

  Future<void> _fetchNotifications({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/notifications'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && (data['success'] == true || data['data'] != null)) {
          List<dynamic> rawList = [];
          if (data['data'] is Map && data['data']['data'] is List) {
            rawList = List<dynamic>.from(data['data']['data'] as List);
          } else if (data['data'] is Map &&
              data['data']['notifications'] is List) {
            rawList = List<dynamic>.from(data['data']['notifications'] as List);
          } else if (data['data'] is List) {
            rawList = List<dynamic>.from(data['data'] as List);
          } else if (data['notifications'] is List) {
            rawList = List<dynamic>.from(data['notifications'] as List);
          }

          final List<JsonMap> parsed = [
            for (final n in rawList)
              if (n is Map) JsonMap.from(n),
          ];

          final int unreadCount = int.tryParse(
                  data['unread_count']?.toString() ?? '') ??
              parsed
                  .where((n) => n['read_at'] == null && n['is_read'] != true)
                  .length;

          ref
              .read(unreadNotificationProvider.notifier)
              .updateCount(unreadCount);

          setState(() {
            _notifications = parsed;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted && !silent) setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(String id) async {
    try {
      await http.patch(
        Uri.parse('$_domain/api/v1/notifications/$id/read'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);
      _fetchNotifications(silent: true);
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    try {
      await http.patch(
        Uri.parse('$_domain/api/v1/notifications/read-all'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);
      _fetchNotifications(silent: true);
    } catch (_) {}
  }

  void _handleNotificationTap(JsonMap item) {
    final String id = item['id']?.toString() ?? '';
    final bool isRead = item['read_at'] != null || item['is_read'] == true;
    if (!isRead && id.isNotEmpty) {
      _markAsRead(id);
    }

    final payload = _extractPayload(item);
    int sellerOrderId =
        int.tryParse(payload['seller_order_id']?.toString() ?? '0') ?? 0;
    final String url = payload['url']?.toString() ?? '';

    if (sellerOrderId <= 0 && url.isNotEmpty) {
      final match = RegExp(r'/orders/(\d+)').firstMatch(url);
      if (match != null) {
        sellerOrderId = int.tryParse(match.group(1) ?? '0') ?? 0;
      }
    }

    if (sellerOrderId > 0) {
      Navigator.push(
        context,
        StorkRoute.fade(
          OrderDetailsScreen(
            orderId: sellerOrderId,
            baseUrl: _domain,
            token: widget.token,
          ),
        ),
      );
    } else if (url.contains('/user/points') || url.contains('/rewards')) {
      Navigator.push(
        context,
        StorkRoute.fade(
          PointsRewardsScreen(
            baseUrl: _domain,
            token: widget.token,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread =
        _notifications.any((n) => n['read_at'] == null && n['is_read'] != true);

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text(
                  'Mark All Read',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchNotifications(),
              child: _notifications.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 90),
                        _buildEmptyState(),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = _notifications[index];
                        final payload = _extractPayload(item);
                        final bool isRead =
                            item['read_at'] != null || item['is_read'] == true;
                        final String type = (payload['type'] ?? 'info')
                            .toString()
                            .toLowerCase();
                        final String title = _resolveTitle(payload);
                        final String message = _resolveMessage(payload);
                        final String timestamp =
                            _formatTimestamp(item, payload);

                        Color iconColor = StorkTheme.primary;
                        IconData iconData = Icons.notifications_active_rounded;
                        if (type == 'success') {
                          iconColor = StorkTheme.success;
                          iconData = Icons.check_circle_rounded;
                        } else if (type == 'danger' || type == 'error') {
                          iconColor = StorkTheme.danger;
                          iconData = Icons.warning_amber_rounded;
                        } else if (type == 'warning') {
                          iconColor = StorkTheme.warning;
                          iconData = Icons.info_outline_rounded;
                        }

                        return InkWell(
                          onTap: () => _handleNotificationTap(item),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: isRead
                                  ? StorkTheme.surface
                                  : StorkTheme.primary.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isRead
                                    ? StorkTheme.borderSubtle
                                    : StorkTheme.primary
                                        .withValues(alpha: 0.35),
                                width: isRead ? 1 : 1.5,
                              ),
                              boxShadow: StorkTheme.softCardShadow,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: iconColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    iconData,
                                    color: iconColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (!isRead)
                                            Container(
                                              width: 7,
                                              height: 7,
                                              margin: const EdgeInsets.only(
                                                  right: 6),
                                              decoration: const BoxDecoration(
                                                color: StorkTheme.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: TextStyle(
                                                fontWeight: isRead
                                                    ? FontWeight.w800
                                                    : FontWeight.w900,
                                                fontSize: 13.5,
                                                color: StorkTheme.primaryDark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (message.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          message,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: StorkTheme.textMain,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.schedule_rounded,
                                            size: 12,
                                            color: StorkTheme.textMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              timestamp,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: StorkTheme.textMuted,
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
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: StorkTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 38,
              color: StorkTheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No Notifications Yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Updates on your orders, E-Wallet top-ups, and rewards will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: StorkTheme.textMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
