import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import 'identity_verification_screen.dart';
import 'login_screen.dart';

class AccountManagementScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final String baseUrl;
  final String token;

  const AccountManagementScreen({
    super.key,
    required this.user,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState
    extends ConsumerState<AccountManagementScreen> {
  late UserModel _currentUser;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  void _showUpdateNameModal() {
    final firstNameController =
        TextEditingController(text: _currentUser.firstName);
    final lastNameController =
        TextEditingController(text: _currentUser.lastName);
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update Full Name',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First Name on ID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last Name on ID',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              try {
                                final response = await http
                                    .patch(
                                      Uri.parse('$_domain/api/v1/account/name'),
                                      headers: {
                                        'Authorization':
                                            'Bearer ${widget.token}',
                                        'Accept': 'application/json',
                                        'Content-Type': 'application/json',
                                      },
                                      body: json.encode({
                                        'first_name':
                                            firstNameController.text.trim(),
                                        'last_name':
                                            lastNameController.text.trim(),
                                      }),
                                    )
                                    .timeout(ApiConfig.requestTimeout);

                                final data = json.decode(response.body);
                                if (response.statusCode == 200 &&
                                    data['success'] == true) {
                                  final updated =
                                      UserModel.fromJson(data['data']);
                                  if (mounted) {
                                    setState(() => _currentUser = updated);
                                  }
                                  ref
                                      .read(authProvider.notifier)
                                      .updateUser(updated);
                                  if (modalContext.mounted) {
                                    Navigator.pop(modalContext);
                                    _showSnackBar('Name updated successfully!',
                                        isError: false);
                                  }
                                } else {
                                  _showSnackBar(data['message'] ??
                                      'Failed to update name.');
                                }
                              } catch (_) {
                                _showSnackBar('Network error occurred.');
                              } finally {
                                if (modalContext.mounted) {
                                  setModalState(() => isSubmitting = false);
                                }
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showUpdatePhoneModal() {
    final phoneController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update Phone Number',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixText: '+63 ',
                      hintText: '9123456789',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              try {
                                final response = await http
                                    .patch(
                                      Uri.parse(
                                          '$_domain/api/v1/account/phone'),
                                      headers: {
                                        'Authorization':
                                            'Bearer ${widget.token}',
                                        'Accept': 'application/json',
                                        'Content-Type': 'application/json',
                                      },
                                      body: json.encode({
                                        'contact_no':
                                            phoneController.text.trim(),
                                      }),
                                    )
                                    .timeout(ApiConfig.requestTimeout);

                                final data = json.decode(response.body);
                                if (response.statusCode == 200 &&
                                    data['success'] == true) {
                                  final updated =
                                      UserModel.fromJson(data['data']);
                                  if (mounted) {
                                    setState(() => _currentUser = updated);
                                  }
                                  ref
                                      .read(authProvider.notifier)
                                      .updateUser(updated);
                                  if (modalContext.mounted) {
                                    Navigator.pop(modalContext);
                                    _showSnackBar(
                                        'Phone number updated successfully!',
                                        isError: false);
                                  }
                                } else {
                                  _showSnackBar(data['message'] ??
                                      'Failed to update phone number.');
                                }
                              } catch (_) {
                                _showSnackBar('Network error occurred.');
                              } finally {
                                if (modalContext.mounted) {
                                  setModalState(() => isSubmitting = false);
                                }
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Update Phone Number'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showChangeEmailModal() {
    final emailCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    bool otpSent = false;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otpSent ? 'Verify New Email OTP' : 'Change Email Address',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!otpSent) ...[
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'New Email Address',
                        hintText: 'name@example.com',
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final newEmail = emailCtrl.text.trim();
                                if (!newEmail.contains('@')) {
                                  _showSnackBar('Enter a valid email address.');
                                  return;
                                }
                                setModalState(() => isSubmitting = true);
                                try {
                                  final response = await http
                                      .post(
                                        Uri.parse(
                                            '$_domain/api/v1/account/email/request-otp'),
                                        headers: {
                                          'Authorization':
                                              'Bearer ${widget.token}',
                                          'Accept': 'application/json',
                                          'Content-Type': 'application/json',
                                        },
                                        body: json.encode({
                                          'email': newEmail,
                                          'new_email': newEmail,
                                        }),
                                      )
                                      .timeout(ApiConfig.requestTimeout);

                                  final data = json.decode(response.body);
                                  if (response.statusCode == 200 &&
                                      data['success'] == true) {
                                    setModalState(() => otpSent = true);
                                  } else {
                                    _showSnackBar(data['message'] ??
                                        'Unable to send verification code.');
                                  }
                                } catch (_) {
                                  _showSnackBar('Network error occurred.');
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(() => isSubmitting = false);
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Send OTP to New Email'),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Enter the 6-digit verification code sent to ${emailCtrl.text.trim()}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '6-Digit Code',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                try {
                                  final response = await http
                                      .post(
                                        Uri.parse(
                                            '$_domain/api/v1/account/email/verify-otp'),
                                        headers: {
                                          'Authorization':
                                              'Bearer ${widget.token}',
                                          'Accept': 'application/json',
                                          'Content-Type': 'application/json',
                                        },
                                        body: json.encode({
                                          'code': otpCtrl.text.trim(),
                                          'email': emailCtrl.text.trim(),
                                          'new_email': emailCtrl.text.trim(),
                                        }),
                                      )
                                      .timeout(ApiConfig.requestTimeout);

                                  final data = json.decode(response.body);
                                  if (response.statusCode == 200 &&
                                      data['success'] == true) {
                                    if (data['data'] is Map) {
                                      final updated = UserModel.fromJson(
                                          Map<String, dynamic>.from(
                                              data['data']));
                                      setState(() => _currentUser = updated);
                                      ref
                                          .read(authProvider.notifier)
                                          .updateUser(updated);
                                    } else {
                                      ref
                                          .read(authProvider.notifier)
                                          .refreshUserProfile();
                                    }
                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                      _showSnackBar(
                                        'Email address updated successfully!',
                                        isError: false,
                                      );
                                    }
                                  } else {
                                    _showSnackBar(
                                        data['message'] ?? 'Invalid OTP code.');
                                  }
                                } catch (_) {
                                  _showSnackBar('Network error occurred.');
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(() => isSubmitting = false);
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Verify & Update Email'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _startPasswordChangeFlow() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: StorkTheme.primary),
      ),
    );

    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/account/password/request-otp'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (mounted) Navigator.pop(context);

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) _showVerifyPasswordOtpModal();
      } else {
        _showSnackBar(data['message'] ?? 'Failed to send OTP.');
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Network error occurred.');
    }
  }

  void _showVerifyPasswordOtpModal() {
    final otpController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter 6-Digit Security OTP',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a verification code to ${_currentUser.email}',
                    style: const TextStyle(
                      color: StorkTheme.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-Digit Code',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              try {
                                final response = await http
                                    .post(
                                      Uri.parse(
                                          '$_domain/api/v1/account/password/verify-otp'),
                                      headers: {
                                        'Authorization':
                                            'Bearer ${widget.token}',
                                        'Accept': 'application/json',
                                        'Content-Type': 'application/json',
                                      },
                                      body: json.encode({
                                        'code': otpController.text.trim(),
                                      }),
                                    )
                                    .timeout(ApiConfig.requestTimeout);

                                final data = json.decode(response.body);
                                if (response.statusCode == 200 &&
                                    data['success'] == true) {
                                  final unlockToken =
                                      data['unlock_token']?.toString() ?? '';
                                  if (modalContext.mounted) {
                                    Navigator.pop(modalContext);
                                  }
                                  if (mounted) {
                                    _showNewPasswordModal(unlockToken);
                                  }
                                } else {
                                  _showSnackBar(
                                      data['message'] ?? 'Invalid code.');
                                }
                              } catch (_) {
                                _showSnackBar('Network error occurred.');
                              } finally {
                                if (modalContext.mounted) {
                                  setModalState(() => isSubmitting = false);
                                }
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Verify Code'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showNewPasswordModal(String unlockToken) {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Set New Password',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password (8+ chars, upper, num, symbol)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              try {
                                final response = await http
                                    .patch(
                                      Uri.parse(
                                          '$_domain/api/v1/account/password'),
                                      headers: {
                                        'Authorization':
                                            'Bearer ${widget.token}',
                                        'Accept': 'application/json',
                                        'Content-Type': 'application/json',
                                      },
                                      body: json.encode({
                                        'unlock_token': unlockToken,
                                        'password':
                                            newPasswordController.text.trim(),
                                        'password_confirmation':
                                            confirmPasswordController.text
                                                .trim(),
                                      }),
                                    )
                                    .timeout(ApiConfig.requestTimeout);

                                final data = json.decode(response.body);
                                if (response.statusCode == 200 &&
                                    data['success'] == true) {
                                  if (modalContext.mounted) {
                                    Navigator.pop(modalContext);
                                    _showSnackBar(
                                        'Password updated successfully!',
                                        isError: false);
                                  }
                                } else {
                                  _showSnackBar(data['message'] ??
                                      'Failed to update password.');
                                }
                              } catch (_) {
                                _showSnackBar('Network error occurred.');
                              } finally {
                                if (modalContext.mounted) {
                                  setModalState(() => isSubmitting = false);
                                }
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Update Password'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openDeleteAccountFlow() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: StorkTheme.primary),
      ),
    );

    List<String> blockers = [];
    Map<String, String> reasonsMap = {
      'privacy': 'Privacy or data concerns',
      'not_using': 'I no longer use Storkia',
      'another_account': 'I have another Storkia account',
      'other': 'Other reason',
    };

    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/account/delete/eligibility'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final d = body is Map ? (body['data'] ?? body) : null;
        if (d is Map) {
          if (d['blockers'] is List) {
            blockers =
                (d['blockers'] as List).map((e) => e.toString()).toList();
          }
          if (d['reasons'] is Map) {
            reasonsMap = (d['reasons'] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Unable to check account deletion eligibility.');
      return;
    }

    if (!mounted) return;

    if (blockers.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(
            'Cannot Delete Account Yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: StorkTheme.danger,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in blockers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '• $b',
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    String selectedReason = reasonsMap.keys.first;
    final noteCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool isDeleting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delete / Archive Your Account',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.danger,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Archiving your account immediately signs you out on all devices and deactivates sign-in.',
                      style: TextStyle(
                        fontSize: 12,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      decoration: const InputDecoration(
                        labelText: 'Reason for leaving *',
                      ),
                      items: reasonsMap.entries
                          .map((e) => DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() => selectedReason = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Additional feedback (Optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Current Password *',
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StorkTheme.danger,
                        ),
                        onPressed: isDeleting
                            ? null
                            : () async {
                                setModalState(() => isDeleting = true);
                                try {
                                  final response = await http
                                      .post(
                                        Uri.parse(
                                            '$_domain/api/v1/account/delete'),
                                        headers: {
                                          'Authorization':
                                              'Bearer ${widget.token}',
                                          'Accept': 'application/json',
                                          'Content-Type': 'application/json',
                                        },
                                        body: json.encode({
                                          'reason': selectedReason,
                                          'note': noteCtrl.text.trim(),
                                          'password': passCtrl.text,
                                        }),
                                      )
                                      .timeout(ApiConfig.requestTimeout);

                                  final data = json.decode(response.body);
                                  if (response.statusCode == 200 &&
                                      data is Map &&
                                      data['success'] == true) {
                                    await ref
                                        .read(authProvider.notifier)
                                        .logout();
                                    if (!mounted) return;
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                        builder: (_) => const LoginScreen(),
                                      ),
                                      (route) => false,
                                    );
                                  } else {
                                    _showSnackBar(data is Map
                                        ? (data['message']?.toString() ??
                                            'Unable to delete account.')
                                        : 'Unable to delete account.');
                                  }
                                } catch (_) {
                                  _showSnackBar('Network error occurred.');
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(() => isDeleting = false);
                                  }
                                }
                              },
                        child: isDeleting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Confirm Account Deletion'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSnackBar(String message, {bool isError = true}) {
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
    final contactNoText = (_currentUser.contactNo ?? '').isNotEmpty
        ? _currentUser.contactNo!
        : 'Not set';

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Account Management & Security'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: StorkTheme.borderSubtle),
            ),
            child: Column(
              children: [
                ListTile(
                  title: const Text(
                    'Full Name',
                    style:
                        TextStyle(fontSize: 12.5, color: StorkTheme.textMuted),
                  ),
                  subtitle: Text(
                    '${_currentUser.firstName} ${_currentUser.lastName}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showUpdateNameModal,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text(
                    'Phone Number',
                    style:
                        TextStyle(fontSize: 12.5, color: StorkTheme.textMuted),
                  ),
                  subtitle: Text(
                    contactNoText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showUpdatePhoneModal,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text(
                    'Email Address (OTP Protected)',
                    style:
                        TextStyle(fontSize: 12.5, color: StorkTheme.textMuted),
                  ),
                  subtitle: Text(
                    _currentUser.email,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showChangeEmailModal,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: StorkTheme.borderSubtle),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded,
                      color: StorkTheme.primary),
                  title: const Text(
                    'Change Password',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                    ),
                  ),
                  subtitle: Text(
                    _currentUser.formattedPasswordLastUpdated ??
                        'Protected by 6-digit email OTP',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: StorkTheme.textMuted,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _startPasswordChangeFlow,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    _currentUser.isIdentityVerified
                        ? Icons.verified_user_rounded
                        : Icons.badge_outlined,
                    color: _currentUser.isIdentityVerified
                        ? StorkTheme.success
                        : StorkTheme.primary,
                  ),
                  title: const Text(
                    'Identity Verification (Government ID)',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                    ),
                  ),
                  subtitle: Text(
                    _currentUser.isIdentityVerified
                        ? 'Verified ✓'
                        : 'Status: ${_currentUser.identityVerificationStatus.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _currentUser.isIdentityVerified
                          ? StorkTheme.success
                          : StorkTheme.textMuted,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      StorkRoute.fade(
                        IdentityVerificationScreen(
                          baseUrl: _domain,
                          token: widget.token,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: StorkTheme.danger.withValues(alpha: 0.35),
              ),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.person_off_outlined,
                color: StorkTheme.danger,
              ),
              title: const Text(
                'Delete / Archive Account',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: StorkTheme.danger,
                ),
              ),
              subtitle: const Text(
                'Deactivate your buyer account once all active orders and disputes are completed.',
                style: TextStyle(fontSize: 11.5, color: StorkTheme.textMuted),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: StorkTheme.danger,
              ),
              onTap: _openDeleteAccountFlow,
            ),
          ),
        ],
      ),
    );
  }
}
