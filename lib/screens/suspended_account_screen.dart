import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

typedef JsonMap = Map<String, dynamic>;

class SuspendedAccountScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final String token;

  const SuspendedAccountScreen({
    super.key,
    required this.user,
    required this.token,
  });

  @override
  ConsumerState<SuspendedAccountScreen> createState() =>
      _SuspendedAccountScreenState();
}

class _SuspendedAccountScreenState extends ConsumerState<SuspendedAccountScreen>
    with WidgetsBindingObserver {
  JsonMap? _sanction;
  bool _isLoading = true;
  bool _isSubmitting = false;
  Timer? _autoSyncTimer;
  final _explanationController = TextEditingController();
  XFile? _pickedFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sanction = widget.user.sanction;
    _refreshSanction();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_isSubmitting) {
        _refreshSanction(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _explanationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isSubmitting) {
      _refreshSanction(silent: true);
    }
  }

  Future<void> _refreshSanction({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    final res = await ApiService.getSanctionStatus(widget.token);
    if (!mounted) return;
    if (res['success'] == true && res['data'] is Map) {
      setState(() {
        _sanction = JsonMap.from(res['data'] as Map);
        _isLoading = false;
      });
      if (_sanction!['is_blocked_from_marketplace'] != true) {
        await ref.read(authProvider.notifier).refreshUserProfile();
        if (!mounted) return;
        final updatedUser = ref.read(authProvider).user ?? widget.user;
        Navigator.pushReplacement(
          context,
          StorkRoute.fade(HomeScreen(user: updatedUser, token: widget.token)),
        );
      }
    } else if (!silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null) {
      setState(() => _pickedFile = file);
    }
  }

  Future<void> _submitAppeal() async {
    final text = _explanationController.text.trim();
    if (text.length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please provide at least 20 characters explaining your appeal.'),
          backgroundColor: StorkTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final res = await ApiService.submitSanctionAppeal(
      token: widget.token,
      explanation: text,
      photoPath: _pickedFile?.path,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      _explanationController.clear();
      setState(() => _pickedFile = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              res['data']?['message'] ?? 'Appeal submitted for Admin review.'),
          backgroundColor: StorkTheme.success,
        ),
      );
      _refreshSanction();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Failed to submit appeal.'),
          backgroundColor: StorkTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPermanent = _sanction?['is_permanently_banned'] == true;
    final isCountdownActive =
        _sanction?['is_temporarily_banned_countdown_active'] == true;
    final canAppeal = _sanction?['can_submit_appeal_now'] == true;
    final strikes = _sanction?['cod_abandonment_strikes'] ?? 0;
    final tempBanEndsAt = _sanction?['temp_ban_ends_at']?.toString() ?? '';
    final JsonMap? latestAppeal = _sanction?['latest_appeal'] is Map
        ? JsonMap.from(_sanction!['latest_appeal'] as Map)
        : null;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Account Restriction Notice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refreshSanction(),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                StorkRoute.fade(const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(
                color: StorkTheme.danger,
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
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: StorkTheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: StorkTheme.danger.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: StorkTheme.softCardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: StorkTheme.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.gpp_bad_outlined,
                              color: StorkTheme.danger,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: StorkTheme.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isPermanent
                                    ? 'PERMANENT ACCOUNT BAN'
                                    : '3/3 COD ABANDONMENT STRIKES ($strikes Strikes)',
                                style: const TextStyle(
                                  color: StorkTheme.danger,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isPermanent
                            ? 'Your Buyer Account Has Been Permanently Banned'
                            : '7-Day Temporary Suspension & Reactivation Portal',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: StorkTheme.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isPermanent
                            ? 'Due to repeated Cash on Delivery (COD) parcel abandonment after a prior reinstatement, your marketplace privileges have been permanently revoked.'
                            : 'Your account reached 3 COD parcel abandonment strikes. After the 7-day temporary suspension countdown ends, you may submit a reactivation appeal for Admin review.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: StorkTheme.textMuted,
                          height: 1.45,
                        ),
                      ),
                      if (isCountdownActive && tempBanEndsAt.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: StorkTheme.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: StorkTheme.warning.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                color: Color(0xFF92400E),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '7-Day Countdown Ends: $tempBanEndsAt',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF92400E),
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
                if (latestAppeal != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Latest Appeal Status',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.primaryDark,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    StorkTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                (latestAppeal['status'] ?? 'pending')
                                    .toString()
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: StorkTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          latestAppeal['appeal_explanation']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            color: StorkTheme.textMain,
                            height: 1.4,
                          ),
                        ),
                        if (latestAppeal['admin_remarks'] != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: StorkTheme.surfaceSubtle,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Admin Remarks: ${latestAppeal['admin_remarks']}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: StorkTheme.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (canAppeal &&
                    (latestAppeal == null ||
                        latestAppeal['status'] != 'pending')) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
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
                          'Submit Reactivation Appeal',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _explanationController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText:
                                'Explain why you missed the COD deliveries and how you will ensure successful receipt going forward (20+ chars)...',
                            fillColor: StorkTheme.surfaceSubtle,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 18),
                          label: Text(
                            _pickedFile != null
                                ? 'Selected: ${_pickedFile!.name}'
                                : 'Attach Supporting Photo (Optional)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient:
                                _isSubmitting ? null : StorkTheme.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitAppeal,
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
                                : const Text('Submit Appeal to Admin'),
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
