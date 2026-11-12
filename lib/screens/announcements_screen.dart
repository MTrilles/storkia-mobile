import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/global_counters_provider.dart';

typedef JsonMap = Map<String, dynamic>;

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
  List<JsonMap> _announcements = [];
  Timer? _autoSyncTimer;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchAnnouncements();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _fetchAnnouncements(silent: true);
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
      _fetchAnnouncements(silent: true);
    }
  }

  List<JsonMap> _extractAnnouncementsList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
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
      final response = await http.get(
        Uri.parse('$_domain/api/v1/announcements'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

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
    try {
      await http.patch(
        Uri.parse('$_domain/api/v1/announcements/$id/read'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);
      _fetchAnnouncements(silent: true);
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    try {
      await http.post(
        Uri.parse('$_domain/api/v1/announcements/read-all'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);
      _fetchAnnouncements(silent: true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _announcements.any((a) => a['is_read'] != true);

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Platform Announcements'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Mark All Read',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
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
              onRefresh: () => _fetchAnnouncements(),
              child: _announcements.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 110),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.campaign_outlined,
                                size: 54,
                                color: StorkTheme.textMuted,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'No platform announcements yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.textMain,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: _announcements.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = _announcements[index];
                        final int id =
                            int.tryParse(item['id']?.toString() ?? '0') ?? 0;
                        final bool isRead = item['is_read'] == true;
                        final bool isPinned = item['is_pinned'] == true;
                        final String title =
                            item['title']?.toString() ?? 'Announcement';
                        final String content = (item['content'] ??
                                item['body'] ??
                                item['message'] ??
                                '')
                            .toString();
                        final String dateStr =
                            (item['published_at'] ?? item['created_at'] ?? '')
                                .toString();

                        return GestureDetector(
                          onTap: () {
                            if (!isRead && id > 0) {
                              _markAsRead(id);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
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
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (isPinned)
                                      Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: StorkTheme.primaryDark,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'PINNED',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    if (!isRead)
                                      Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
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
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
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
                                const SizedBox(height: 6),
                                Text(
                                  content,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: StorkTheme.textMain,
                                    height: 1.4,
                                  ),
                                ),
                                if (dateStr.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: StorkTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
