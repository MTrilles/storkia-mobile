import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/global_counters_provider.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'legal_policies_screen.dart';
import 'register_screen.dart';
import 'suspended_account_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final res = await ApiService.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      final user = UserModel.fromJson(res['data']['user']);
      final token = res['data']['access_token'].toString();

      await ref.read(authProvider.notifier).login(user, token);
      syncAllBuyerCounters(ref, token);

      if (!mounted) return;
      if (user.isBlockedFromMarketplace) {
        Navigator.pushReplacement(
          context,
          StorkRoute.fade(
            SuspendedAccountScreen(user: user, token: token),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          StorkRoute.fade(
            HomeScreen(user: user, token: token),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Login failed.'),
          backgroundColor: StorkTheme.danger,
        ),
      );
    }
  }

  void _openForgotPasswordModal() {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final tokenCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool codeSent = false;
    bool isSubmitting = false;
    bool showPass = false;
    String? modalError;
    String? modalSuccess;

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
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: StorkTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: StorkTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.lock_reset_rounded,
                            color: StorkTheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                codeSent
                                    ? 'Reset Your Password'
                                    : 'Forgot Password?',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                codeSent
                                    ? 'Enter the reset token sent to your email.'
                                    : 'Receive a password reset token via email.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: StorkTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailCtrl,
                      enabled: !codeSent && !isSubmitting,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Registered Email Address *',
                        prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                      ),
                    ),
                    if (codeSent) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Reset Token / Code *',
                          prefixIcon: Icon(Icons.pin_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: !showPass,
                        decoration: InputDecoration(
                          labelText:
                              'New Password (8+ chars, upper, num, symbol) *',
                          prefixIcon:
                              const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              showPass
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              size: 18,
                            ),
                            onPressed: () =>
                                setModalState(() => showPass = !showPass),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmCtrl,
                        obscureText: !showPass,
                        decoration: const InputDecoration(
                          labelText: 'Confirm New Password *',
                          prefixIcon:
                              Icon(Icons.verified_user_outlined, size: 20),
                        ),
                      ),
                    ],
                    if (modalError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: StorkTheme.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: StorkTheme.danger.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 17,
                              color: StorkTheme.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                modalError!,
                                style: const TextStyle(
                                  color: StorkTheme.danger,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (modalSuccess != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: StorkTheme.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: StorkTheme.success.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 17,
                              color: StorkTheme.success,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                modalSuccess!,
                                style: const TextStyle(
                                  color: StorkTheme.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final email = emailCtrl.text.trim();
                                if (email.isEmpty || !email.contains('@')) {
                                  setModalState(() {
                                    modalError =
                                        'Please enter a valid email address.';
                                  });
                                  return;
                                }

                                if (!codeSent) {
                                  setModalState(() {
                                    isSubmitting = true;
                                    modalError = null;
                                    modalSuccess = null;
                                  });
                                  try {
                                    final response = await http
                                        .post(
                                          Uri.parse(
                                              '${ApiConfig.baseUrl}/forgot-password'),
                                          headers: {
                                            'Accept': 'application/json',
                                            'Content-Type': 'application/json',
                                          },
                                          body: json.encode({'email': email}),
                                        )
                                        .timeout(ApiConfig.requestTimeout);

                                    final data = json.decode(response.body);
                                    if (response.statusCode == 200 &&
                                        (data['success'] == true ||
                                            data['status'] != null)) {
                                      setModalState(() {
                                        codeSent = true;
                                        modalSuccess = data['message']
                                                ?.toString() ??
                                            'Password reset instructions sent to your email.';
                                      });
                                    } else {
                                      setModalState(() {
                                        modalError =
                                            data['message']?.toString() ??
                                                'Unable to send reset link.';
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
                                } else {
                                  if (tokenCtrl.text.trim().isEmpty) {
                                    setModalState(() {
                                      modalError =
                                          'Please enter the reset token from your email.';
                                    });
                                    return;
                                  }
                                  if (passCtrl.text.length < 8) {
                                    setModalState(() {
                                      modalError =
                                          'Password must be at least 8 characters.';
                                    });
                                    return;
                                  }
                                  if (passCtrl.text != confirmCtrl.text) {
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
                                        .post(
                                          Uri.parse(
                                              '${ApiConfig.baseUrl}/reset-password'),
                                          headers: {
                                            'Accept': 'application/json',
                                            'Content-Type': 'application/json',
                                          },
                                          body: json.encode({
                                            'email': email,
                                            'token': tokenCtrl.text.trim(),
                                            'password': passCtrl.text,
                                            'password_confirmation':
                                                confirmCtrl.text,
                                          }),
                                        )
                                        .timeout(ApiConfig.requestTimeout);

                                    final data = json.decode(response.body);
                                    if (response.statusCode == 200 &&
                                        (data['success'] == true ||
                                            data['status'] != null)) {
                                      if (modalContext.mounted) {
                                        Navigator.pop(modalContext);
                                      }
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              data['message']?.toString() ??
                                                  'Password reset successfully! You may now sign in.',
                                            ),
                                            backgroundColor: StorkTheme.success,
                                          ),
                                        );
                                      }
                                    } else {
                                      setModalState(() {
                                        modalError = data['message']
                                                ?.toString() ??
                                            'Invalid or expired reset token.';
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
                            : Text(codeSent
                                ? 'Reset Password'
                                : 'Send Reset Instructions'),
                      ),
                    ),
                    if (!codeSent)
                      Center(
                        child: TextButton(
                          onPressed: () => setModalState(() => codeSent = true),
                          child: const Text(
                            'Already have a reset token?',
                            style: TextStyle(fontSize: 12),
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
    );
  }

  void _openLegalPolicy(int tabIndex) {
    Navigator.push(
      context,
      StorkRoute.fade(LegalPoliciesScreen(initialTab: tabIndex)),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: StorkTheme.primaryDark,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _buildPolicyFooterLink(String label, int tabIndex) {
    return InkWell(
      onTap: () => _openLegalPolicy(tabIndex),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: StorkTheme.primaryDark,
            decoration: TextDecoration.underline,
            decorationColor: StorkTheme.borderSubtle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surface,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: StorkTheme.brandGradient,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Welcome Back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in to your Storkia Buyer account to shop verified stores, track parcels, and earn Coins.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - 40)
                            .clamp(0.0, double.infinity),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                          bottom: 22,
                                        ),
                                        child: Image.asset(
                                          'assets/pink-storkia-maximized.webp',
                                          height: 58,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.storefront_rounded,
                                                size: 32,
                                                color: StorkTheme.primary,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'STORKIA',
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  color: StorkTheme.primaryDark,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    _buildFieldLabel('EMAIL ADDRESS'),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                        hintText: 'name@example.com',
                                        fillColor: StorkTheme.surfaceSubtle,
                                        prefixIcon: Icon(
                                          Icons.mail_outline_rounded,
                                          size: 20,
                                          color: StorkTheme.primaryDark,
                                        ),
                                      ),
                                      validator: (val) {
                                        if (val == null || val.trim().isEmpty) {
                                          return 'Please enter your email address.';
                                        }
                                        if (!val.contains('@')) {
                                          return 'Please enter a valid email address.';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 18),
                                    _buildFieldLabel('PASSWORD'),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: !_isPasswordVisible,
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => _handleLogin(),
                                      decoration: InputDecoration(
                                        hintText: 'Enter your password',
                                        fillColor: StorkTheme.surfaceSubtle,
                                        prefixIcon: const Icon(
                                          Icons.lock_outline_rounded,
                                          size: 20,
                                          color: StorkTheme.primaryDark,
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _isPasswordVisible
                                                ? Icons.visibility_rounded
                                                : Icons.visibility_off_rounded,
                                            size: 20,
                                            color: StorkTheme.textMuted,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _isPasswordVisible =
                                                  !_isPasswordVisible;
                                            });
                                          },
                                        ),
                                      ),
                                      validator: (val) {
                                        if (val == null || val.isEmpty) {
                                          return 'Please enter your password.';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: GestureDetector(
                                        onTap: _openForgotPasswordModal,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          child: Text(
                                            'Forgot Password?',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: StorkTheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Container(
                                      width: double.infinity,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: _isLoading
                                            ? null
                                            : StorkTheme.brandGradient,
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: _isLoading
                                            ? null
                                            : [
                                                BoxShadow(
                                                  color: StorkTheme.primary
                                                      .withValues(alpha: 0.28),
                                                  blurRadius: 14,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed:
                                            _isLoading ? null : _handleLogin,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2.3,
                                                ),
                                              )
                                            : const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    'Sign In to Storkia',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 18,
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: StorkTheme.surfaceSubtle,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: StorkTheme.borderSubtle,
                                        ),
                                      ),
                                      child: Wrap(
                                        alignment: WrapAlignment.center,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          const Text(
                                            'New to Storkia Marketplace?',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: StorkTheme.textMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                StorkRoute.slideUp(
                                                  const RegisterScreen(),
                                                ),
                                              );
                                            },
                                            child: const Text(
                                              'Create a Buyer Account →',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: StorkTheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Column(
                                  children: [
                                    const Divider(height: 1),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'By signing in, you agree to Storkia’s official policies:',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: StorkTheme.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 4,
                                      runSpacing: 2,
                                      children: [
                                        _buildPolicyFooterLink(
                                          'Terms & Conditions',
                                          0,
                                        ),
                                        const Text(
                                          '•',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: StorkTheme.textMuted,
                                          ),
                                        ),
                                        _buildPolicyFooterLink(
                                          'Privacy Policy',
                                          1,
                                        ),
                                        const Text(
                                          '•',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: StorkTheme.textMuted,
                                          ),
                                        ),
                                        _buildPolicyFooterLink(
                                          'Cookie Policy',
                                          2,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
