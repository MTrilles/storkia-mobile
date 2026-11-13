import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_theme.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;

class SellerReportsScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const SellerReportsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<SellerReportsScreen> createState() => _SellerReportsScreenState();
}

class _SellerReportsScreenState extends State<SellerReportsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  JsonList _reports = [];
  Timer? _autoSyncTimer;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchReports(silent: false);
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _fetchReports(silent: true);
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
      _fetchReports(silent: true);
    }
  }

  JsonList _extractReportsList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) JsonMap.from(item),
      ];
    }
    if (raw is Map) {
      for (final key in ['reports', 'seller_reports', 'items', 'data']) {
        if (raw.containsKey(key) && raw[key] != null && raw[key] != raw) {
          final extracted = _extractReportsList(raw[key]);
          if (extracted.isNotEmpty) return extracted;
        }
      }
      for (final value in raw.values) {
        if (value is List) {
          final extracted = _extractReportsList(value);
          if (extracted.isNotEmpty) return extracted;
        }
      }
    }
    return [];
  }

  Future<void> _fetchReports({bool silent = true}) async {
    if (!silent && _reports.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/seller-reports'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final parsed = _extractReportsList(
          body is Map ? (body['data'] ?? body) : body,
        );
        setState(() {
          _reports = parsed;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  void _showPhotoPreview(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: StorkTheme.surface,
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Report Evidence Photo',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primaryDark,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.62,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Unable to load image.'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text('My Store Reports (${_reports.length})'),
      ),
      body: _isLoading && _reports.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchReports(silent: true),
              child: _reports.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 90),
                        Center(
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: StorkTheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.flag_outlined,
                              size: 38,
                              color: StorkTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Store Reports Submitted',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Any store violation reports you submit for Storkia Compliance Admin review will be tracked here.',
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
                      padding: const EdgeInsets.all(14),
                      itemCount: _reports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final r = _reports[index];
                        final String reportNo =
                            r['report_number']?.toString() ?? '';
                        final String status =
                            (r['status'] ?? 'pending').toString().toLowerCase();
                        final String storeName = (r['seller_name'] ??
                                (r['seller_profile'] is Map
                                    ? r['seller_profile']['business_name']
                                    : 'Reported Store'))
                            .toString();
                        final String category =
                            (r['reason_label'] ?? r['reason_category'] ?? '')
                                .toString();
                        final String desc = r['description']?.toString() ?? '';
                        final String? adminNote = r['admin_note']?.toString();
                        final String? adminAction =
                            r['admin_action']?.toString();
                        final String? orderNo = (r['seller_order_number'] ??
                                (r['seller_order'] is Map
                                    ? r['seller_order']['seller_order_number']
                                    : null))
                            ?.toString();
                        final String createdAt =
                            (r['created_at_formatted'] ?? r['created_at'] ?? '')
                                .toString();
                        final List<dynamic> rawPhotos = r['evidence_photos']
                                is List
                            ? List<dynamic>.from(r['evidence_photos'] as List)
                            : <dynamic>[];

                        final bool isResolved = status == 'resolved';
                        final bool isDismissed = status == 'dismissed';

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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.storefront_rounded,
                                          size: 17,
                                          color: StorkTheme.primaryDark,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            reportNo.isNotEmpty
                                                ? '$storeName ($reportNo)'
                                                : storeName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isResolved
                                          ? StorkTheme.success
                                              .withValues(alpha: 0.14)
                                          : (isDismissed
                                              ? StorkTheme.borderSubtle
                                              : StorkTheme.warning
                                                  .withValues(alpha: 0.16)),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      status.replaceAll('_', ' ').toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: isResolved
                                            ? StorkTheme.success
                                            : (isDismissed
                                                ? StorkTheme.textMuted
                                                : const Color(0xFF92400E)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: StorkTheme.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Category: $category',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: StorkTheme.primary,
                                      ),
                                    ),
                                  ),
                                  if (orderNo != null && orderNo.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: StorkTheme.brandLight
                                            .withValues(alpha: 0.45),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Order #$orderNo',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: StorkTheme.primaryDark,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                desc,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: StorkTheme.textMain,
                                  height: 1.4,
                                ),
                              ),
                              if (rawPhotos.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final p in rawPhotos)
                                      Builder(builder: (context) {
                                        final rawPath = p is Map
                                            ? (p['url'] ?? p['path'] ?? '')
                                                .toString()
                                            : p.toString();
                                        final url = ApiConfig.storageUrl(
                                            rawPath, _domain);
                                        return GestureDetector(
                                          onTap: () => _showPhotoPreview(url),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Image.network(
                                              url,
                                              width: 54,
                                              height: 54,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                width: 54,
                                                height: 54,
                                                color: StorkTheme.surfaceSubtle,
                                                child: const Icon(
                                                  Icons
                                                      .image_not_supported_outlined,
                                                  size: 18,
                                                  color: StorkTheme.textMuted,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              ],
                              if (createdAt.isNotEmpty) ...[
                                const SizedBox(height: 8),
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
                                        'Submitted: $createdAt',
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
                              ],
                              if ((adminAction != null &&
                                      adminAction.trim().isNotEmpty) ||
                                  (adminNote != null &&
                                      adminNote.trim().isNotEmpty)) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: StorkTheme.surfaceSubtle,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: StorkTheme.borderSubtle),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (adminAction != null &&
                                          adminAction.trim().isNotEmpty)
                                        Text(
                                          'Admin Action: ${adminAction.replaceAll('_', ' ').toUpperCase()}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: StorkTheme.primary,
                                          ),
                                        ),
                                      if (adminNote != null &&
                                          adminNote.trim().isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 3),
                                          child: Text(
                                            'Admin Note: $adminNote',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: StorkTheme.primaryDark,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
