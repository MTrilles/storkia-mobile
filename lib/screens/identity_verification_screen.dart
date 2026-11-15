import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'legal_policies_screen.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StringMap = Map<String, String>;

class IdentityVerificationScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;

  const IdentityVerificationScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends ConsumerState<IdentityVerificationScreen>
    with WidgetsBindingObserver {
  Timer? _wsDebounceTimer;
  bool _isLoading = true;
  bool _isSubmitting = false;

  String _status = 'not_started';
  String? _rejectionReason;
  String _selectedIdType = 'drivers_license';
  String _selectedMethod = 'upload';
  XFile? _frontFile;
  XFile? _backFile;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  static const List<StringMap> _idTypes = [
    {'key': 'drivers_license', 'label': "Driver's License"},
    {'key': 'passport', 'label': 'Philippine Passport'},
    {'key': 'identity_card', 'label': 'National ID / UMID / Postal ID'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchVerificationStatus(silent: false);
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'compliance' ||
        event.scope == 'notification' ||
        event.scope == 'general') {
      _wsDebounceTimer?.cancel();
      _wsDebounceTimer = Timer(const Duration(milliseconds: 260), () {
        if (mounted && !_isSubmitting) {
          _fetchVerificationStatus(silent: true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsDebounceTimer?.cancel();
    WebSocketService.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isSubmitting) {
      _fetchVerificationStatus(silent: true);
    }
  }

  Future<void> _fetchVerificationStatus({bool silent = true}) async {
    if (!silent && _status == 'not_started') {
      setState(() => _isLoading = true);
    }
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('$_domain/api/v1/account/identity-verification'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final d = body is Map ? (body['data'] ?? body) : null;
        if (d is Map) {
          final verif = d['verification'] is Map
              ? JsonMap.from(d['verification'] as Map)
              : JsonMap.from(d);

          final String newStatus =
              (verif['status'] ?? d['status'] ?? 'not_started').toString();
          setState(() {
            _status = newStatus;
            _rejectionReason = verif['rejection_reason']?.toString();
            _isLoading = false;
          });
          ref.read(authProvider.notifier).refreshUserProfile();
          return;
        }
      }
    } catch (_) {}
    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage({required bool isFront, required bool camera}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final len = await picked.length();
    if (len > 5 * 1024 * 1024) {
      _showToast('ID photo must not exceed 5MB.');
      return;
    }

    setState(() {
      _selectedMethod = camera ? 'camera' : 'upload';
      if (isFront) {
        _frontFile = picked;
      } else {
        _backFile = picked;
      }
    });
  }

  Future<void> _submitVerification() async {
    if (_frontFile == null) {
      _showToast('Please provide a clear photo of the front of your ID.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$_domain/api/v1/account/identity-verification'),
      );
      req.headers.addAll(ApiService.buildHeaders(widget.token));
      req.fields['id_type'] = _selectedIdType;
      req.fields['method'] = _selectedMethod;

      req.files.add(
        await http.MultipartFile.fromPath('front_image', _frontFile!.path),
      );
      if (_backFile != null) {
        req.files.add(
          await http.MultipartFile.fromPath('back_image', _backFile!.path),
        );
      }

      final streamed = await ApiService.httpClient
          .send(req)
          .timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (!mounted) return;

      final data = json.decode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        _showToast(
          data['message']?.toString() ??
              'Government ID submitted for Storkia Admin review!',
          isError: false,
        );
        _fetchVerificationStatus(silent: true);
      } else {
        String err = data is Map
            ? (data['message']?.toString() ?? 'Failed to submit ID.')
            : 'Failed to submit ID.';
        if (data is Map &&
            data['errors'] is Map &&
            (data['errors'] as Map).isNotEmpty) {
          final first = (data['errors'] as Map).values.first;
          if (first is List && first.isNotEmpty) {
            err = first.first.toString();
          }
        }
        _showToast(err);
      }
    } catch (_) {
      _showToast('Network error occurred while uploading ID.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showToast(String message, {bool isError = true}) {
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
                  : Icons.check_circle_outline_rounded,
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
        backgroundColor: isError ? StorkTheme.danger : StorkTheme.success,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isVerified = _status == 'verified';
    final bool isPending = _status == 'pending';
    final bool isFailed = _status == 'failed' || _status == 'rejected';

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Identity Verification (KYC)'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchVerificationStatus(silent: true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: (!isVerified && !isPending && !isFailed)
                          ? StorkTheme.brandGradient
                          : null,
                      color: isVerified
                          ? StorkTheme.success.withValues(alpha: 0.1)
                          : (isPending
                              ? StorkTheme.warning.withValues(alpha: 0.14)
                              : (isFailed
                                  ? StorkTheme.danger.withValues(alpha: 0.1)
                                  : null)),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isVerified
                            ? StorkTheme.success.withValues(alpha: 0.4)
                            : (isPending
                                ? StorkTheme.warning.withValues(alpha: 0.4)
                                : (isFailed
                                    ? StorkTheme.danger.withValues(alpha: 0.4)
                                    : Colors.transparent)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: (!isVerified && !isPending && !isFailed)
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                isVerified
                                    ? Icons.verified_user_rounded
                                    : (isPending
                                        ? Icons.hourglass_top_rounded
                                        : Icons.badge_outlined),
                                color: isVerified
                                    ? StorkTheme.success
                                    : (isPending
                                        ? const Color(0xFF92400E)
                                        : ((!isVerified &&
                                                !isPending &&
                                                !isFailed)
                                            ? Colors.white
                                            : StorkTheme.danger)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isVerified
                                    ? 'Identity Verified ✓'
                                    : (isPending
                                        ? 'Verification Under Admin Review'
                                        : (isFailed
                                            ? 'Verification Rejected — Please Resubmit'
                                            : 'Verify Your Government ID')),
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color:
                                      (!isVerified && !isPending && !isFailed)
                                          ? Colors.white
                                          : StorkTheme.textMain,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isVerified
                              ? 'Your Valid Government ID is verified. Return & Refund protection is unlocked on your account.'
                              : (isPending
                                  ? 'Storkia Admin is reviewing your submitted ID. This page updates automatically once approved.'
                                  : 'A verified Government ID protects buyers and merchants and is required before requesting order returns or refunds.'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: (!isVerified && !isPending && !isFailed)
                                ? Colors.white.withValues(alpha: 0.88)
                                : StorkTheme.textMuted,
                            height: 1.4,
                          ),
                        ),
                        if (isFailed &&
                            _rejectionReason != null &&
                            _rejectionReason!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Admin Reason: "$_rejectionReason"',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.danger,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isVerified && !isPending) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: StorkTheme.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: StorkTheme.borderSubtle),
                        boxShadow: StorkTheme.softCardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '1. SELECT GOVERNMENT ID TYPE *',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: StorkTheme.primaryDark,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final item in _idTypes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () => setState(() {
                                  _selectedIdType = item['key']!;
                                }),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: _selectedIdType == item['key']
                                        ? StorkTheme.primary
                                            .withValues(alpha: 0.08)
                                        : StorkTheme.surfaceSubtle,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _selectedIdType == item['key']
                                          ? StorkTheme.primary
                                          : StorkTheme.borderSubtle,
                                      width: _selectedIdType == item['key']
                                          ? 1.5
                                          : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _selectedIdType == item['key']
                                            ? Icons.radio_button_checked_rounded
                                            : Icons.radio_button_off_rounded,
                                        color: _selectedIdType == item['key']
                                            ? StorkTheme.primary
                                            : StorkTheme.textMuted,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          item['label']!,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight:
                                                _selectedIdType == item['key']
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                            color: StorkTheme.textMain,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const Divider(height: 24),
                          const Text(
                            '2. FRONT OF GOVERNMENT ID (REQUIRED, MAX 5MB) *',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: StorkTheme.primaryDark,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickImage(isFront: true, camera: false),
                                  icon: const Icon(Icons.photo_library_outlined,
                                      size: 17),
                                  label: const Text('Gallery'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickImage(isFront: true, camera: true),
                                  icon: const Icon(Icons.camera_alt_outlined,
                                      size: 17),
                                  label: const Text('Camera'),
                                ),
                              ),
                            ],
                          ),
                          if (_frontFile != null) ...[
                            const SizedBox(height: 10),
                            Stack(
                              alignment: Alignment.topRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    File(_frontFile!.path),
                                    height: 150,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _frontFile = null),
                                  icon: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          const Text(
                            '3. BACK OF GOVERNMENT ID (OPTIONAL, MAX 5MB)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: StorkTheme.primaryDark,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickImage(isFront: false, camera: false),
                                  icon: const Icon(Icons.photo_library_outlined,
                                      size: 17),
                                  label: const Text('Gallery'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickImage(isFront: false, camera: true),
                                  icon: const Icon(Icons.camera_alt_outlined,
                                      size: 17),
                                  label: const Text('Camera'),
                                ),
                              ),
                            ],
                          ),
                          if (_backFile != null) ...[
                            const SizedBox(height: 10),
                            Stack(
                              alignment: Alignment.topRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    File(_backFile!.path),
                                    height: 150,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _backFile = null),
                                  icon: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: _isSubmitting
                                  ? null
                                  : StorkTheme.brandGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ElevatedButton(
                              onPressed:
                                  _isSubmitting ? null : _submitVerification,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
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
                                  : const Text('Submit ID for Verification'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  StorkRoute.fade(
                                    const LegalPoliciesScreen(initialTab: 1),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.privacy_tip_outlined,
                                  size: 16),
                              label: const Text(
                                'How your ID is protected (Privacy Policy)',
                                style: TextStyle(fontSize: 12),
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
    );
  }
}
