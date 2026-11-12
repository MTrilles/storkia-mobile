import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';

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
  Timer? _autoSyncTimer;

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
    _fetchProfile();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!_isSavingUsername && !_isUploadingAvatar) {
        _fetchProfile(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchProfile(silent: true);
    }
  }

  Future<void> _fetchProfile({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/profile'),
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
          final JsonMap profileMap = d['profile'] is Map
              ? Map<String, dynamic>.from(d['profile'] as Map)
              : (d['buyer_profile'] is Map
                  ? Map<String, dynamic>.from(d['buyer_profile'] as Map)
                  : Map<String, dynamic>.from(d));

          final JsonMap? userMap = d['user'] is Map
              ? Map<String, dynamic>.from(d['user'] as Map)
              : null;
          final JsonMap? nestedBuyerProfile = userMap?['buyer_profile'] is Map
              ? Map<String, dynamic>.from(userMap!['buyer_profile'] as Map)
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
    final clean = _usernameController.text.trim();
    if (clean.length < 3) {
      _showToast('Username must be at least 3 characters.');
      return;
    }

    setState(() => _isSavingUsername = true);
    try {
      final response = await http
          .patch(
            Uri.parse('$_domain/api/v1/profile/username'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({'username': clean}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
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

    setState(() => _isUploadingAvatar = true);
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$_domain/api/v1/profile/avatar'),
      );
      req.headers['Authorization'] = 'Bearer ${widget.token}';
      req.headers['Accept'] = 'application/json';
      req.files.add(await http.MultipartFile.fromPath('avatar', picked.path));

      final streamed = await req.send().timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (!mounted) return;

      final data = json.decode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
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
    setState(() => _isUploadingAvatar = true);
    try {
      final response = await http.delete(
        Uri.parse('$_domain/api/v1/profile/avatar'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

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
    final user = ref.watch(authProvider).user;
    final String effectiveAvatar = _avatarUrl.isNotEmpty
        ? _avatarUrl
        : ((user?.avatarPath != null && user!.avatarPath!.isNotEmpty)
            ? ApiConfig.storageUrl(user.avatarPath, _domain)
            : '');

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Public Buyer Profile'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: StorkTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: StorkTheme.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 46,
                            backgroundColor:
                                StorkTheme.primary.withValues(alpha: 0.12),
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
                      const SizedBox(height: 12),
                      Text(
                        user?.fullName ?? 'Buyer',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.textMain,
                        ),
                      ),
                      if (_username.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$_username',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: StorkTheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isUploadingAvatar
                                ? null
                                : _pickAndUploadAvatar,
                            icon: const Icon(Icons.photo_camera_outlined,
                                size: 17),
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
                                foregroundColor: StorkTheme.danger,
                                side:
                                    const BorderSide(color: StorkTheme.danger),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 17),
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
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: StorkTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PUBLIC USERNAME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Your username identifies your public profile across Storkia reviews and product Q&A.',
                        style: TextStyle(
                          fontSize: 12,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _usernameController,
                        enabled: _canChangeUsername && !_isSavingUsername,
                        maxLength: 30,
                        decoration: const InputDecoration(
                          labelText: 'Username (letters, numbers, _ .)',
                          prefixText: '@',
                          counterText: '',
                        ),
                      ),
                      if (!_canChangeUsername &&
                          _nextUsernameChangeDate != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Username can be changed again on $_nextUsernameChangeDate.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: StorkTheme.warning,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: (!_canChangeUsername || _isSavingUsername)
                              ? null
                              : _updateUsername,
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
    );
  }
}
