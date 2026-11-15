import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/global_counters_provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;

  const AnnouncementsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  String _selectedFilter = 'all';
  List<JsonMap> _announcements = [];

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchAnnouncements();
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'marketplace' ||
        event.scope == 'notification' ||
        event.scope == 'general') {
      _fetchAnnouncements(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WebSocketService.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchAnnouncements(silent: true);
    }
  }

  List<JsonMap> _extractAnnouncementsList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) JsonMap.from(item),
      ];
    }
    if (raw is Map) {
      for (final key in ['announcements', 'items', 'entries', 'data']) {
        if (raw.containsKey(key) && raw[key] != null && raw[key] != raw) {
          final extracted = _extractAnnouncementsList(raw[key]);
          if (extracted.isNotEmpty) return extracted;
        }
      }
      for (final value in raw.values) {
        if (value is List) {
          final extracted = _extractAnnouncementsList(value);
          if (extracted.isNotEmpty) return extracted;
        }
      }
    }
    return [];
  }

  Future<void> _fetchAnnouncements({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('$_domain/api/v1/announcements'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final List<JsonMap> parsed = _extractAnnouncementsList(
          body is Map ? (body['data'] ?? body) : body,
        );
        final unreadCount = parsed.where((a) => a['is_read'] != true).length;
        ref.read(unreadAnnouncementProvider.notifier).updateCount(unreadCount);

        setState(() {
          _announcements = parsed;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(int id) async {
    HapticFeedback.selectionClick();
    try {
      await ApiService.httpClient
          .patch(
            Uri.parse('$_domain/api/v1/announcements/$id/read'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);
      _fetchAnnouncements(silent: true);
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    HapticFeedback.lightImpact();
    try {
      await ApiService.httpClient
          .post(
            Uri.parse('$_domain/api/v1/announcements/read-all'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);
      _fetchAnnouncements(silent: true);
    } catch (_) {}
  }

  List<JsonMap> get _filteredAnnouncements {
    if (_selectedFilter == 'unread') {
      return _announcements.where((a) => a['is_read'] != true).toList();
    }
    if (_selectedFilter == 'pinned') {
      return _announcements.where((a) => a['is_pinned'] == true).toList();
    }
    return _announcements;
  }

  Widget _buildFilterChip({
    required String keyValue,
    required String label,
    required int count,
  }) {
    final bool isSelected = _selectedFilter == keyValue;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = keyValue);
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: isSelected ? StorkTheme.brandGradient : null,
          color: isSelected ? null : StorkTheme.surfaceSubtle,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? StorkTheme.primary : StorkTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : StorkTheme.textMain,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : StorkTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? StorkTheme.primary : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        _announcements.where((a) => a['is_read'] != true).length;
    final pinnedCount =
        _announcements.where((a) => a['is_pinned'] == true).length;
    final hasUnread = unreadCount > 0;
    final visibleList = _filteredAnnouncements;
    final isCompactAppBar = MediaQuery.sizeOf(context).width < 360;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Platform Announcements'),
        ),
        actions: [
          if (hasUnread)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompactAppBar ? 8 : 12,
                    vertical: 6,
                  ),
                ),
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: Text(
                  isCompactAppBar ? 'Read All' : 'Mark All Read',
                  style: const TextStyle(
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
          : Column(
              children: [
                if (_announcements.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: StorkTheme.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            keyValue: 'all',
                            label: 'All Updates',
                            count: _announcements.length,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            keyValue: 'unread',
                            label: 'Unread',
                            count: unreadCount,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            keyValue: 'pinned',
                            label: 'Pinned',
                            count: pinnedCount,
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    color: StorkTheme.primary,
                    onRefresh: () => _fetchAnnouncements(),
                    child: visibleList.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(28),
                            children: [
                              const SizedBox(height: 70),
                              Center(
                                child: Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: StorkTheme.primary
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.campaign_outlined,
                                    size: 38,
                                    color: StorkTheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _announcements.isEmpty
                                    ? 'No Platform Announcements Yet'
                                    : 'No Matching Announcements',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Official Storkia marketplace updates, system notices, and promo alerts will appear here.',
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
                            padding: const EdgeInsets.all(16),
                            itemCount: visibleList.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = visibleList[index];
                              final int id =
                                  int.tryParse(item['id']?.toString() ?? '0') ??
                                      0;
                              final bool isRead = item['is_read'] == true;
                              final bool isPinned = item['is_pinned'] == true;
                              final String title =
                                  item['title']?.toString() ?? 'Announcement';
                              final String content = (item['content'] ??
                                      item['body'] ??
                                      item['message'] ??
                                      '')
                                  .toString();
                              final String dateStr = (item['published_at'] ??
                                      item['created_at'] ??
                                      '')
                                  .toString();

                              return InkWell(
                                onTap: () {
                                  if (!isRead && id > 0) {
                                    _markAsRead(id);
                                  }
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isRead
                                        ? StorkTheme.surface
                                        : StorkTheme.primary
                                            .withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isRead
                                          ? StorkTheme.borderSubtle
                                          : StorkTheme.primary
                                              .withValues(alpha: 0.38),
                                      width: isRead ? 1 : 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.025),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          if (isPinned)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    StorkTheme.primaryDark,
                                                    StorkTheme.primary,
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.push_pin_rounded,
                                                    size: 10,
                                                    color: Colors.white,
                                                  ),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'PINNED',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (!isRead)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: StorkTheme.primary,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'NEW',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (isPinned || !isRead)
                                        const SizedBox(height: 8),
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: StorkTheme.primaryDark,
                                          height: 1.3,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        content,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: StorkTheme.textMain,
                                          height: 1.45,
                                        ),
                                      ),
                                      if (dateStr.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.schedule_rounded,
                                              size: 13,
                                              color: StorkTheme.textMuted,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                dateStr,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: StorkTheme.textMuted,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
