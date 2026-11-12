import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_theme.dart';

typedef JsonMap = Map<String, dynamic>;

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
  List<JsonMap> _reports = [];
  Timer? _autoSyncTimer;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchReports();
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

  List<JsonMap> _extractReportsList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
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

  Future<void> _fetchReports({bool silent = false}) async {
    if (!silent) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('My Store Reports'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchReports(),
              child: _reports.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 110),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.flag_outlined,
                                size: 54,
                                color: StorkTheme.textMuted,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'No store reports submitted',
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
                      itemCount: _reports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final r = _reports[index];
                        final String reportNo =
                            r['report_number']?.toString() ?? '';
                        final String status =
                            (r['status'] ?? 'pending').toString();
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

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: StorkTheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: StorkTheme.borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$storeName ($reportNo)',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: StorkTheme.primaryDark,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: status == 'resolved'
                                          ? StorkTheme.success
                                              .withValues(alpha: 0.14)
                                          : StorkTheme.warning
                                              .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: status == 'resolved'
                                            ? StorkTheme.success
                                            : const Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Category: $category',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: StorkTheme.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                desc,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: StorkTheme.textMain,
                                ),
                              ),
                              if (adminNote != null &&
                                  adminNote.trim().isNotEmpty) ...[
                                const Divider(height: 18),
                                Text(
                                  'Admin Resolution Note: $adminNote',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: StorkTheme.primaryDark,
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
