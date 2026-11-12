import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';

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
  Timer? _autoSyncTimer;
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
    _fetchVerificationStatus();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_isSubmitting) {
        _fetchVerificationStatus(silent: true);
      }
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
      _fetchVerificationStatus(silent: true);
    }
  }

  Future<void> _fetchVerificationStatus({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/account/identity-verification'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final d = body is Map ? (body['data'] ?? body) : null;
        if (d is Map) {
          final verif = d['verification'] is Map
              ? Map<String, dynamic>.from(d['verification'] as Map)
              : Map<String, dynamic>.from(d);

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

    setState(() => _isSubmitting = true);
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$_domain/api/v1/account/identity-verification'),
      );
      req.headers['Authorization'] = 'Bearer ${widget.token}';
      req.headers['Accept'] = 'application/json';
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

      final streamed = await req.send().timeout(ApiConfig.requestTimeout);
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
        _fetchVerificationStatus();
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? StorkTheme.danger : StorkTheme.success,
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isVerified
                        ? StorkTheme.success.withValues(alpha: 0.1)
                        : (isPending
                            ? StorkTheme.warning.withValues(alpha: 0.14)
                            : (isFailed
                                ? StorkTheme.danger.withValues(alpha: 0.1)
                                : StorkTheme.surface)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isVerified
                          ? StorkTheme.success.withValues(alpha: 0.4)
                          : (isPending
                              ? StorkTheme.warning.withValues(alpha: 0.4)
                              : (isFailed
                                  ? StorkTheme.danger.withValues(alpha: 0.4)
                                  : StorkTheme.borderSubtle)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isVerified
                                ? Icons.verified_user_rounded
                                : (isPending
                                    ? Icons.hourglass_top_rounded
                                    : Icons.badge_outlined),
                            color: isVerified
                                ? StorkTheme.success
                                : (isPending
                                    ? const Color(0xFF92400E)
                                    : StorkTheme.primaryDark),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isVerified
                                  ? 'Identity Verified'
                                  : (isPending
                                      ? 'Verification Under Admin Review'
                                      : (isFailed
                                          ? 'Verification Rejected — Please Resubmit'
                                          : 'Verify Your Government ID')),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.textMain,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isVerified
                            ? 'Your Valid Government ID is verified. Return & Refund protection is unlocked on your account.'
                            : (isPending
                                ? 'Storkia Admin is reviewing your submitted ID. This page updates automatically once approved.'
                                : 'A verified Government ID protects buyers and merchants and is required before requesting order returns or refunds.'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: StorkTheme.textMuted,
                          height: 1.4,
                        ),
                      ),
                      if (isFailed &&
                          _rejectionReason != null &&
                          _rejectionReason!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Admin Reason: "$_rejectionReason"',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.danger,
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
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: StorkTheme.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '1. SELECT GOVERNMENT ID TYPE *',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final item in _idTypes)
                          InkWell(
                            onTap: () =>
                                setState(() => _selectedIdType = item['key']!),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
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
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: StorkTheme.textMain,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const Divider(height: 24),
                        const Text(
                          '2. FRONT OF GOVERNMENT ID (REQUIRED) *',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.textMuted,
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_frontFile!.path),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const Text(
                          '3. BACK OF GOVERNMENT ID (OPTIONAL)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.textMuted,
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_backFile!.path),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed:
                                _isSubmitting ? null : _submitVerification,
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
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
