import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

typedef JsonMap = Map<String, dynamic>;

class ProfileScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;

  const ProfileScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with WidgetsBindingObserver {
  final TextEditingController _usernameController = TextEditingController();
  Timer? _wsDebounceTimer;

  bool _isLoading = true;
  bool _isSavingUsername = false;
  bool _isUploadingAvatar = false;

  String _username = '';
  String _avatarUrl = '';
  bool _canChangeUsername = true;
  String? _nextUsernameChangeDate;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final cachedUser = ref.read(authProvider).user;
    if (cachedUser != null) {
      if (cachedUser.username != null && cachedUser.username!.isNotEmpty) {
        _username = cachedUser.username!;
        _usernameController.text = cachedUser.username!;
      }
      if (cachedUser.avatarPath != null && cachedUser.avatarPath!.isNotEmpty) {
        _avatarUrl = ApiConfig.storageUrl(cachedUser.avatarPath, _domain);
      }
    }
    _fetchProfile(silent: false);
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'user' || event.scope == 'general') {
      _wsDebounceTimer?.cancel();
      _wsDebounceTimer = Timer(const Duration(milliseconds: 260), () {
        if (mounted && !_isSavingUsername && !_isUploadingAvatar) {
          _fetchProfile(silent: true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsDebounceTimer?.cancel();
    WebSocketService.removeListener(_onRealtimeEvent);
    _usernameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_isSavingUsername &&
        !_isUploadingAvatar) {
      _fetchProfile(silent: true);
    }
  }

  Future<void> _copyUsername() async {
    if (_username.isEmpty) return;
    final tag = '@$_username';
    await Clipboard.setData(ClipboardData(text: tag));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    _showToast('Copied username: $tag', isError: false);
  }

  Future<void> _fetchProfile({bool silent = true}) async {
    if (!silent && _username.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('$_domain/api/v1/profile'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final d = body is Map ? (body['data'] ?? body) : null;
        if (d is Map) {
          final JsonMap profileMap = d['profile'] is Map
              ? JsonMap.from(d['profile'] as Map)
              : (d['buyer_profile'] is Map
                  ? JsonMap.from(d['buyer_profile'] as Map)
                  : JsonMap.from(d));

          final JsonMap? userMap =
              d['user'] is Map ? JsonMap.from(d['user'] as Map) : null;
          final JsonMap? nestedBuyerProfile = userMap?['buyer_profile'] is Map
              ? JsonMap.from(userMap!['buyer_profile'] as Map)
              : null;

          final String fetchedUsername = (profileMap['username'] ??
                  d['username'] ??
                  nestedBuyerProfile?['username'] ??
                  userMap?['username'] ??
                  '')
              .toString()
              .trim();

          final String rawAvatar = (profileMap['avatar_url'] ??
                  profileMap['avatar_path'] ??
                  profileMap['photo_url'] ??
                  d['avatar_url'] ??
                  d['avatar_path'] ??
                  d['photo_url'] ??
                  nestedBuyerProfile?['avatar_url'] ??
                  nestedBuyerProfile?['avatar_path'] ??
                  userMap?['avatar_url'] ??
                  userMap?['avatar_path'] ??
                  '')
              .toString()
              .trim();

          setState(() {
            _username = fetchedUsername;
            if (!silent || _usernameController.text.isEmpty) {
              _usernameController.text = fetchedUsername;
            }
            _avatarUrl = rawAvatar.isNotEmpty
                ? ApiConfig.storageUrl(rawAvatar, _domain)
                : '';
            _canChangeUsername = (profileMap['can_change_username'] ??
                    d['can_change_username']) !=
                false;
            _nextUsernameChangeDate = (profileMap['next_change_at'] ??
                    d['next_change_at'] ??
                    profileMap['username_cooldown_ends_at'])
                ?.toString();
            _isLoading = false;
          });

          final currentUser = ref.read(authProvider).user;
          if (currentUser != null) {
            ref.read(authProvider.notifier).updateUser(
                  currentUser.copyWith(
                    username:
                        fetchedUsername.isNotEmpty ? fetchedUsername : null,
                    avatarPath: rawAvatar.isNotEmpty ? rawAvatar : null,
                    clearAvatar: rawAvatar.isEmpty,
                  ),
                );
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateUsername() async {
    final clean = _usernameController.text.trim().toLowerCase();
    if (clean.length < 3 || clean.length > 30) {
      _showToast('Username must be between 3 and 30 characters.');
      return;
    }
    if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(clean)) {
      _showToast(
        'Use only lowercase letters, numbers, underscores (_), or dots (.).',
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _isSavingUsername = true;
    });
    try {
      final response = await ApiService.httpClient
          .patch(
            Uri.parse('$_domain/api/v1/profile/username'),
            headers: ApiService.buildHeaders(widget.token, isJson: true),
            body: json.encode({'username': clean}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        HapticFeedback.mediumImpact();
        _showToast(
          data['message']?.toString() ?? 'Username updated successfully!',
          isError: false,
        );
        await _fetchProfile(silent: true);
        await ref.read(authProvider.notifier).refreshUserProfile();
      } else {
        String err = data is Map
            ? (data['message']?.toString() ?? 'Failed to update username.')
            : 'Failed to update username.';
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
      _showToast('Network error occurred.');
    } finally {
      if (mounted) setState(() => _isSavingUsername = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final len = await picked.length();
    if (len > 5 * 1024 * 1024) {
      _showToast('Avatar photo must not exceed 5MB.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isUploadingAvatar = true);
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$_domain/api/v1/profile/avatar'),
      );
      req.headers.addAll(ApiService.buildHeaders(widget.token));
      req.files.add(await http.MultipartFile.fromPath('avatar', picked.path));

      final streamed = await ApiService.httpClient
          .send(req)
          .timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (!mounted) return;

      final data = json.decode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        HapticFeedback.mediumImpact();
        _showToast(
          data['message']?.toString() ?? 'Profile photo updated!',
          isError: false,
        );
        await _fetchProfile(silent: true);
        await ref.read(authProvider.notifier).refreshUserProfile();
      } else {
        _showToast(
          data is Map
              ? (data['message']?.toString() ?? 'Failed to upload avatar.')
              : 'Failed to upload avatar.',
        );
      }
    } catch (_) {
      _showToast('Network error occurred while uploading photo.');
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    HapticFeedback.lightImpact();
    setState(() => _isUploadingAvatar = true);
    try {
      final response = await ApiService.httpClient
          .delete(
            Uri.parse('$_domain/api/v1/profile/avatar'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        setState(() => _avatarUrl = '');
        final currentUser = ref.read(authProvider).user;
        if (currentUser != null) {
          await ref
              .read(authProvider.notifier)
              .updateUser(currentUser.copyWith(clearAvatar: true));
        }
        _showToast(
          data['message']?.toString() ?? 'Profile photo removed.',
          isError: false,
        );
      } else {
        _showToast('Unable to remove photo.');
      }
    } catch (_) {
      _showToast('Network error occurred.');
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
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
    final user = ref.watch(authProvider).user;
    final String effectiveAvatar = _avatarUrl.isNotEmpty
        ? _avatarUrl
        : ((user?.avatarPath != null && user!.avatarPath!.isNotEmpty)
            ? ApiConfig.storageUrl(user.avatarPath, _domain)
            : '');

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Public Buyer Profile'),
        ),
      ),
      body: _isLoading && _username.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: () => _fetchProfile(silent: true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: StorkTheme.brandGradient,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: StorkTheme.primaryDark.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap:
                              _isUploadingAvatar ? null : _pickAndUploadAvatar,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 46,
                                  backgroundColor: Colors.white,
                                  backgroundImage: effectiveAvatar.isNotEmpty
                                      ? NetworkImage(effectiveAvatar)
                                      : null,
                                  child: effectiveAvatar.isEmpty
                                      ? Text(
                                          (user?.firstName.isNotEmpty ?? false)
                                              ? user!.firstName[0].toUpperCase()
                                              : 'B',
                                          style: const TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.w900,
                                            color: StorkTheme.primary,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: StorkTheme.primaryDark,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 15,
                                  color: Colors.white,
                                ),
                              ),
                              if (_isUploadingAvatar)
                                const Positioned.fill(
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: StorkTheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          user?.fullName ?? 'Buyer',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        if (_username.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _copyUsername,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '@$_username',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: StorkTheme.brandLight,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.copy_rounded,
                                    size: 12,
                                    color: StorkTheme.brandLight,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isUploadingAvatar
                                  ? null
                                  : _pickAndUploadAvatar,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: StorkTheme.primaryDark,
                              ),
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                size: 17,
                              ),
                              label: Text(
                                effectiveAvatar.isNotEmpty
                                    ? 'Change Avatar'
                                    : 'Upload Avatar',
                              ),
                            ),
                            if (effectiveAvatar.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed:
                                    _isUploadingAvatar ? null : _removeAvatar,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 17,
                                ),
                                label: const Text('Remove'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color:
                                    StorkTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.alternate_email_rounded,
                                color: StorkTheme.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'PUBLIC @USERNAME',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: StorkTheme.primaryDark,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your username identifies your public profile across Storkia reviews and product Q&A.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: StorkTheme.textMuted,
                            height: 1.38,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _usernameController,
                          enabled: _canChangeUsername && !_isSavingUsername,
                          maxLength: 30,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9_.]'),
                            ),
                            LengthLimitingTextInputFormatter(30),
                          ],
                          decoration: const InputDecoration(
                            labelText:
                                'Username (3\u201330 chars: letters, numbers, _ .)',
                            prefixText: '@',
                            counterText: '',
                            fillColor: StorkTheme.surfaceSubtle,
                          ),
                        ),
                        if (!_canChangeUsername &&
                            _nextUsernameChangeDate != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: StorkTheme.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    StorkTheme.warning.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 16,
                                  color: Color(0xFF92400E),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Username can be changed again on $_nextUsernameChangeDate.',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: (!_canChangeUsername || _isSavingUsername)
                                ? null
                                : StorkTheme.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ElevatedButton(
                            onPressed:
                                (!_canChangeUsername || _isSavingUsername)
                                    ? null
                                    : _updateUsername,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isSavingUsername
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save Username'),
                          ),
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
