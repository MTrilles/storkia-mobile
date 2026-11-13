import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import 'identity_verification_screen.dart';
import 'legal_policies_screen.dart';
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

  String _extractApiError(dynamic data, String fallback) {
    if (data is Map) {
      if (data['errors'] is Map && (data['errors'] as Map).isNotEmpty) {
        final firstVal = (data['errors'] as Map).values.first;
        if (firstVal is List && firstVal.isNotEmpty) {
          return firstVal.first.toString();
        }
        return firstVal.toString();
      }
      if (data['message'] != null && data['message'].toString().isNotEmpty) {
        return data['message'].toString();
      }
    }
    return fallback;
  }

  Widget _buildSheetHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Color accentColor = StorkTheme.primary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: StorkTheme.borderSubtle,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.18),
                    accentColor.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.25),
                ),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: accentColor == StorkTheme.danger
                          ? StorkTheme.danger
                          : StorkTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: StorkTheme.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModalErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: StorkTheme.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StorkTheme.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: StorkTheme.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: StorkTheme.danger,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpdateNameModal() {
    final firstNameController =
        TextEditingController(text: _currentUser.firstName);
    final lastNameController =
        TextEditingController(text: _currentUser.lastName);
    bool isSubmitting = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 14,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSheetHeader(
                      icon: Icons.badge_outlined,
                      title: 'Update Full Name',
                      subtitle:
                          'Make sure this matches the legal name on your government ID.',
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: firstNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'First Name on ID *',
                        prefixIcon:
                            Icon(Icons.person_outline_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: lastNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Last Name on ID *',
                        prefixIcon:
                            Icon(Icons.person_outline_rounded, size: 20),
                      ),
                    ),
                    if (modalError != null) _buildModalErrorBanner(modalError!),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final fName = firstNameController.text.trim();
                                final lName = lastNameController.text.trim();
                                final nameRegex = RegExp(r'^[A-Za-z\s]+$');
                                if (fName.isEmpty || lName.isEmpty) {
                                  setModalState(() {
                                    modalError =
                                        'Both first name and last name are required.';
                                  });
                                  return;
                                }
                                if (!nameRegex.hasMatch(fName) ||
                                    !nameRegex.hasMatch(lName)) {
                                  setModalState(() {
                                    modalError =
                                        'Names may only contain letters and spaces.';
                                  });
                                  return;
                                }
                                setModalState(() {
                                  isSubmitting = true;
                                  modalError = null;
                                });
                                try {
                                  final response = await http
                                      .patch(
                                        Uri.parse(
                                            '$_domain/api/v1/account/name'),
                                        headers: {
                                          'Authorization':
                                              'Bearer ${widget.token}',
                                          'Accept': 'application/json',
                                          'Content-Type': 'application/json',
                                        },
                                        body: json.encode({
                                          'first_name': fName,
                                          'last_name': lName,
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
                                          'Name updated successfully!',
                                          isError: false);
                                    }
                                  } else {
                                    setModalState(() {
                                      modalError = _extractApiError(
                                          data, 'Failed to update name.');
                                    });
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError = 'Network error occurred.';
                                  });
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
              ),
            );
          },
        );
      },
    );
  }

  void _showUpdatePhoneModal() {
    String existingPhone = (_currentUser.contactNo ?? '').trim();
    existingPhone = existingPhone.replaceAll(RegExp(r'\D'), '');
    if (existingPhone.startsWith('63') && existingPhone.length == 12) {
      existingPhone = '0${existingPhone.substring(2)}';
    }
    final phoneController = TextEditingController(text: existingPhone);
    bool isSubmitting = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 14,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSheetHeader(
                      icon: Icons.phone_iphone_rounded,
                      title: 'Update Phone Number',
                      subtitle:
                          'Enter a valid Philippine mobile number (09XXXXXXXXX or 9XXXXXXXXX).',
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      onChanged: (_) {
                        if (modalError != null) {
                          setModalState(() => modalError = null);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number *',
                        prefixText: '+63 ',
                        hintText: '09171234567 or 9171234567',
                        prefixIcon: Icon(Icons.call_outlined, size: 20),
                      ),
                    ),
                    if (modalError != null) _buildModalErrorBanner(modalError!),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final rawDigits = phoneController.text
                                    .trim()
                                    .replaceAll(RegExp(r'\D'), '');
                                if (!RegExp(r'^0?9\d{9}$')
                                    .hasMatch(rawDigits)) {
                                  setModalState(() {
                                    modalError =
                                        'Please enter a valid 11-digit (09XXXXXXXXX) or 10-digit (9XXXXXXXXX) Philippine mobile number.';
                                  });
                                  return;
                                }
                                setModalState(() {
                                  isSubmitting = true;
                                  modalError = null;
                                });
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
                                          'contact_no': rawDigits,
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
                                    setModalState(() {
                                      modalError = _extractApiError(data,
                                          'Failed to update phone number.');
                                    });
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError = 'Network error occurred.';
                                  });
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
    int resendCooldown = 0;
    Timer? cooldownTimer;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void startTimer(int seconds) {
              cooldownTimer?.cancel();
              setModalState(() => resendCooldown = seconds);
              cooldownTimer =
                  Timer.periodic(const Duration(seconds: 1), (timer) {
                if (!modalContext.mounted) {
                  timer.cancel();
                  return;
                }
                if (resendCooldown > 0) {
                  setModalState(() => resendCooldown--);
                } else {
                  timer.cancel();
                }
              });
            }

            Future<void> sendEmailOtpRequest() async {
              final newEmail = emailCtrl.text.trim();
              if (newEmail.isEmpty || !newEmail.contains('@')) {
                setModalState(() {
                  modalError = 'Please enter a valid email address.';
                });
                return;
              }
              setModalState(() {
                isSubmitting = true;
                modalError = null;
              });
              try {
                final response = await http
                    .post(
                      Uri.parse('$_domain/api/v1/account/email/request-otp'),
                      headers: {
                        'Authorization': 'Bearer ${widget.token}',
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
                if (response.statusCode == 200 && data['success'] == true) {
                  setModalState(() {
                    otpSent = true;
                    modalError = null;
                  });
                  startTimer(
                      int.tryParse(data['cooldown']?.toString() ?? '60') ?? 60);
                } else {
                  final wait =
                      int.tryParse(data['cooldown']?.toString() ?? '0') ?? 0;
                  if (wait > 0) startTimer(wait);
                  setModalState(() {
                    modalError = _extractApiError(
                        data, 'Unable to send verification code.');
                  });
                }
              } catch (_) {
                setModalState(() {
                  modalError = 'Network error occurred.';
                });
              } finally {
                if (modalContext.mounted) {
                  setModalState(() => isSubmitting = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 14,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSheetHeader(
                      icon: Icons.mark_email_read_outlined,
                      title: otpSent
                          ? 'Verify New Email OTP'
                          : 'Change Email Address',
                      subtitle: otpSent
                          ? 'Enter the 6-digit verification code sent to ${emailCtrl.text.trim()}'
                          : 'We will send a 6-digit security code to verify your new email address.',
                    ),
                    const SizedBox(height: 18),
                    if (!otpSent) ...[
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'New Email Address *',
                          hintText: 'name@example.com',
                          prefixIcon: Icon(Icons.email_outlined, size: 20),
                        ),
                      ),
                      if (modalError != null)
                        _buildModalErrorBanner(modalError!),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isSubmitting ? null : sendEmailOtpRequest,
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
                      TextField(
                        controller: otpCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          labelText: '6-Digit Verification Code *',
                          counterText: '',
                          prefixIcon: Icon(Icons.pin_outlined, size: 20),
                        ),
                      ),
                      if (modalError != null)
                        _buildModalErrorBanner(modalError!),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (otpCtrl.text.trim().length < 6) {
                                    setModalState(() {
                                      modalError =
                                          'Please enter the 6-digit verification code.';
                                    });
                                    return;
                                  }
                                  setModalState(() {
                                    isSubmitting = true;
                                    modalError = null;
                                  });
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
                                      cooldownTimer?.cancel();
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
                                      setModalState(() {
                                        modalError = _extractApiError(
                                            data, 'Invalid OTP code.');
                                      });
                                    }
                                  } catch (_) {
                                    setModalState(() {
                                      modalError = 'Network error occurred.';
                                    });
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
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () {
                                    setModalState(() {
                                      otpSent = false;
                                      otpCtrl.clear();
                                      modalError = null;
                                    });
                                  },
                            child: const Text('Change Email'),
                          ),
                          TextButton(
                            onPressed: (resendCooldown > 0 || isSubmitting)
                                ? null
                                : sendEmailOtpRequest,
                            child: Text(
                              resendCooldown > 0
                                  ? 'Resend in ${resendCooldown}s'
                                  : 'Resend Code',
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
        );
      },
    ).whenComplete(() => cooldownTimer?.cancel());
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
        final int cooldown =
            int.tryParse(data['cooldown']?.toString() ?? '60') ?? 60;
        if (mounted) _showVerifyPasswordOtpModal(initialCooldown: cooldown);
      } else {
        _showSnackBar(_extractApiError(data, 'Failed to send OTP.'));
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Network error occurred.');
    }
  }

  void _showVerifyPasswordOtpModal({int initialCooldown = 60}) {
    final otpController = TextEditingController();
    bool isSubmitting = false;
    int resendCooldown = initialCooldown;
    Timer? cooldownTimer;
    String? modalError;
    bool timerInitialized = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void startTimer(int seconds) {
              cooldownTimer?.cancel();
              setModalState(() => resendCooldown = seconds);
              cooldownTimer =
                  Timer.periodic(const Duration(seconds: 1), (timer) {
                if (!modalContext.mounted) {
                  timer.cancel();
                  return;
                }
                if (resendCooldown > 0) {
                  setModalState(() => resendCooldown--);
                } else {
                  timer.cancel();
                }
              });
            }

            if (!timerInitialized) {
              timerInitialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (modalContext.mounted) startTimer(initialCooldown);
              });
            }

            Future<void> resendPasswordOtp() async {
              setModalState(() {
                isSubmitting = true;
                modalError = null;
              });
              try {
                final response = await http.post(
                  Uri.parse('$_domain/api/v1/account/password/request-otp'),
                  headers: {
                    'Authorization': 'Bearer ${widget.token}',
                    'Accept': 'application/json',
                  },
                ).timeout(ApiConfig.requestTimeout);
                final data = json.decode(response.body);
                if (response.statusCode == 200 && data['success'] == true) {
                  startTimer(
                      int.tryParse(data['cooldown']?.toString() ?? '60') ?? 60);
                } else {
                  setModalState(() {
                    modalError =
                        _extractApiError(data, 'Failed to resend OTP.');
                  });
                }
              } catch (_) {
                setModalState(() {
                  modalError = 'Network error occurred.';
                });
              } finally {
                if (modalContext.mounted) {
                  setModalState(() => isSubmitting = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 14,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSheetHeader(
                      icon: Icons.shield_outlined,
                      title: 'Enter 6-Digit Security OTP',
                      subtitle:
                          'We sent a verification code to ${_currentUser.email}',
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: '6-Digit Code *',
                        counterText: '',
                        prefixIcon: Icon(Icons.lock_clock_outlined, size: 20),
                      ),
                    ),
                    if (modalError != null) _buildModalErrorBanner(modalError!),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (otpController.text.trim().length < 6) {
                                  setModalState(() {
                                    modalError =
                                        'Please enter the 6-digit verification code.';
                                  });
                                  return;
                                }
                                setModalState(() {
                                  isSubmitting = true;
                                  modalError = null;
                                });
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
                                    cooldownTimer?.cancel();
                                    final unlockToken =
                                        data['unlock_token']?.toString() ?? '';
                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                    }
                                    if (mounted) {
                                      _showNewPasswordModal(unlockToken);
                                    }
                                  } else {
                                    setModalState(() {
                                      modalError = _extractApiError(
                                          data, 'Invalid verification code.');
                                    });
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError = 'Network error occurred.';
                                  });
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
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: (resendCooldown > 0 || isSubmitting)
                            ? null
                            : resendPasswordOtp,
                        child: Text(
                          resendCooldown > 0
                              ? 'Resend code in ${resendCooldown}s'
                              : 'Resend Verification Code',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => cooldownTimer?.cancel());
  }

  void _showNewPasswordModal(String unlockToken) {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool showNew = false;
    bool showConfirm = false;
    bool isSubmitting = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final pass = newPasswordController.text;
            final bool hasMinLength = pass.length >= 8;
            final bool hasUpper = RegExp(r'[A-Z]').hasMatch(pass);
            final bool hasNumber = RegExp(r'[0-9]').hasMatch(pass);
            final bool hasSymbol = RegExp(r'[\W_]').hasMatch(pass);
            final bool allMet =
                hasMinLength && hasUpper && hasNumber && hasSymbol;

            Widget buildReqItem(String label, bool met) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: met
                      ? StorkTheme.success.withValues(alpha: 0.1)
                      : StorkTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: met
                        ? StorkTheme.success.withValues(alpha: 0.35)
                        : StorkTheme.borderSubtle,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      met
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 13,
                      color: met ? StorkTheme.success : StorkTheme.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: met ? FontWeight.w800 : FontWeight.w600,
                        color: met ? StorkTheme.success : StorkTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 14,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSheetHeader(
                      icon: Icons.key_rounded,
                      title: 'Set New Password',
                      subtitle:
                          'Create a strong password that meets all 4 security criteria below.',
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: newPasswordController,
                      obscureText: !showNew,
                      onChanged: (_) => setModalState(() => modalError = null),
                      decoration: InputDecoration(
                        labelText: 'New Password *',
                        prefixIcon:
                            const Icon(Icons.lock_outline_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            showNew
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            size: 18,
                          ),
                          onPressed: () =>
                              setModalState(() => showNew = !showNew),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        buildReqItem('8+ characters', hasMinLength),
                        buildReqItem('1 uppercase', hasUpper),
                        buildReqItem('1 number', hasNumber),
                        buildReqItem('1 special symbol', hasSymbol),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: !showConfirm,
                      onChanged: (_) => setModalState(() => modalError = null),
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password *',
                        prefixIcon:
                            const Icon(Icons.verified_user_outlined, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            showConfirm
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            size: 18,
                          ),
                          onPressed: () =>
                              setModalState(() => showConfirm = !showConfirm),
                        ),
                      ),
                    ),
                    if (modalError != null) _buildModalErrorBanner(modalError!),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (!allMet) {
                                  setModalState(() {
                                    modalError =
                                        'Please satisfy all 4 password requirements.';
                                  });
                                  return;
                                }
                                if (newPasswordController.text !=
                                    confirmPasswordController.text) {
                                  setModalState(() {
                                    modalError =
                                        'Password confirmation does not match.';
                                  });
                                  return;
                                }
                                setModalState(() {
                                  isSubmitting = true;
                                  modalError = null;
                                });
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
                                              newPasswordController.text,
                                          'password_confirmation':
                                              confirmPasswordController.text,
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
                                      if (mounted) {
                                        setState(() => _currentUser = updated);
                                      }
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
                                          'Password updated successfully!',
                                          isError: false);
                                    }
                                  } else {
                                    setModalState(() {
                                      modalError = _extractApiError(
                                          data, 'Failed to update password.');
                                    });
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError = 'Network error occurred.';
                                  });
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: StorkTheme.danger),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cannot Delete Account Yet',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.danger,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in blockers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: StorkTheme.danger,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          b,
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
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
    String? modalError;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSheetHeader(
                      icon: Icons.person_off_outlined,
                      title: 'Delete / Archive Your Account',
                      subtitle:
                          'Archiving your account immediately signs you out on all devices and deactivates sign-in.',
                      accentColor: StorkTheme.danger,
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Reason for leaving *',
                      ),
                      items: reasonsMap.entries
                          .map((e) => DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  overflow: TextOverflow.ellipsis,
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
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                      ),
                    ),
                    if (modalError != null) _buildModalErrorBanner(modalError!),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StorkTheme.danger,
                        ),
                        onPressed: isDeleting
                            ? null
                            : () async {
                                if (passCtrl.text.isEmpty) {
                                  setModalState(() {
                                    modalError =
                                        'Please enter your current password.';
                                  });
                                  return;
                                }
                                setModalState(() {
                                  isDeleting = true;
                                  modalError = null;
                                });
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
                                    setModalState(() {
                                      modalError = _extractApiError(
                                          data, 'Unable to delete account.');
                                    });
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError = 'Network error occurred.';
                                  });
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

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: StorkTheme.textMuted,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Widget? badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        badge,
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: StorkTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: StorkTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactNoText = (_currentUser.contactNo ?? '').isNotEmpty
        ? _currentUser.contactNo!
        : 'Not set';
    final initials = [
      if (_currentUser.firstName.isNotEmpty) _currentUser.firstName[0],
      if (_currentUser.lastName.isNotEmpty) _currentUser.lastName[0],
    ].join().toUpperCase();

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Account & Security'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [StorkTheme.primaryDark, StorkTheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: StorkTheme.primaryDark.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    initials.isNotEmpty ? initials : 'U',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_currentUser.firstName} ${_currentUser.lastName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentUser.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _currentUser.isIdentityVerified
                              ? StorkTheme.success.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _currentUser.isIdentityVerified
                                  ? Icons.verified_rounded
                                  : Icons.shield_outlined,
                              size: 13,
                              color: StorkTheme.brandLight,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _currentUser.isIdentityVerified
                                    ? 'Government ID Verified'
                                    : 'ID Status: ${_currentUser.identityVerificationStatus.toUpperCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionLabel('PERSONAL INFORMATION'),
          Container(
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: StorkTheme.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSettingTile(
                  icon: Icons.person_outline_rounded,
                  iconColor: StorkTheme.primary,
                  label: 'Full Name',
                  value: '${_currentUser.firstName} ${_currentUser.lastName}',
                  onTap: _showUpdateNameModal,
                ),
                const Divider(height: 1, indent: 72),
                _buildSettingTile(
                  icon: Icons.phone_iphone_rounded,
                  iconColor: StorkTheme.primaryDark,
                  label: 'Phone Number',
                  value: contactNoText,
                  onTap: _showUpdatePhoneModal,
                ),
                const Divider(height: 1, indent: 72),
                _buildSettingTile(
                  icon: Icons.alternate_email_rounded,
                  iconColor: StorkTheme.primary,
                  label: 'Email Address',
                  value: _currentUser.email,
                  badge: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: StorkTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'OTP PROTECTED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primary,
                      ),
                    ),
                  ),
                  onTap: _showChangeEmailModal,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionLabel('SECURITY & VERIFICATION'),
          Container(
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: StorkTheme.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSettingTile(
                  icon: Icons.lock_outline_rounded,
                  iconColor: StorkTheme.primary,
                  label: 'Change Password',
                  value: _currentUser.formattedPasswordLastUpdated ??
                      'Protected by 6-digit email OTP',
                  onTap: _startPasswordChangeFlow,
                ),
                const Divider(height: 1, indent: 72),
                _buildSettingTile(
                  icon: _currentUser.isIdentityVerified
                      ? Icons.verified_user_rounded
                      : Icons.badge_outlined,
                  iconColor: _currentUser.isIdentityVerified
                      ? StorkTheme.success
                      : StorkTheme.primary,
                  label: 'Identity Verification (Government ID)',
                  value: _currentUser.isIdentityVerified
                      ? 'Verified ✓'
                      : 'Status: ${_currentUser.identityVerificationStatus.toUpperCase()}',
                  onTap: () {
                    Navigator.push(
                      context,
                      StorkRoute.fade(
                        IdentityVerificationScreen(
                          baseUrl: _domain,
                          token: widget.token,
                        ),
                      ),
                    ).then((_) {
                      ref.read(authProvider.notifier).refreshUserProfile();
                    });
                  },
                ),
                const Divider(height: 1, indent: 72),
                _buildSettingTile(
                  icon: Icons.gavel_rounded,
                  iconColor: StorkTheme.primaryDark,
                  label: 'Legal & Platform Policies',
                  value: 'Terms & Conditions, Privacy & Cookie Policies',
                  onTap: () {
                    Navigator.push(
                      context,
                      StorkRoute.fade(
                        const LegalPoliciesScreen(initialTab: 0),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionLabel('ACCOUNT CLOSURE'),
          Container(
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: StorkTheme.danger.withValues(alpha: 0.3),
              ),
            ),
            child: InkWell(
              onTap: _openDeleteAccountFlow,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: StorkTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.person_off_outlined,
                        color: StorkTheme.danger,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delete / Archive Account',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.danger,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Deactivate your buyer account once all active orders and disputes are completed.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: StorkTheme.textMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: StorkTheme.danger,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
