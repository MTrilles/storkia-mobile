import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  void _showPopupToast(String message, {bool isError = true}) {
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

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();

    setState(() => _isLoading = true);

    final res = await ApiService.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      HapticFeedback.mediumImpact();
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
      HapticFeedback.heavyImpact();
      _showPopupToast(
        res['message']?.toString() ?? 'Login failed.',
        isError: true,
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
            final mediaQuery = MediaQuery.of(ctx);
            final bottomInset = mediaQuery.viewInsets.bottom;
            final safeBottom = mediaQuery.viewPadding.bottom;

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: mediaQuery.size.height * 0.90,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 14,
                  bottom:
                      bottomInset + (bottomInset > 0 ? 16 : safeBottom + 24),
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
                                    fontSize: 16.5,
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
                          prefixIcon:
                              Icon(Icons.mail_outline_rounded, size: 20),
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
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 20,
                            ),
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
                                    _showPopupToast(
                                      'Please enter a valid email address.',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (!codeSent) {
                                    setModalState(() => isSubmitting = true);
                                    try {
                                      final response = await ApiService
                                          .httpClient
                                          .post(
                                            Uri.parse(
                                                '${ApiConfig.baseUrl}/forgot-password'),
                                            headers: {
                                              'Accept': 'application/json',
                                              'Content-Type':
                                                  'application/json',
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
                                        });
                                        _showPopupToast(
                                          data['message']?.toString() ??
                                              'Password reset instructions sent to your email.',
                                          isError: false,
                                        );
                                      } else {
                                        _showPopupToast(
                                          data['message']?.toString() ??
                                              'Unable to send reset link.',
                                          isError: true,
                                        );
                                      }
                                    } catch (_) {
                                      _showPopupToast(
                                        'Network error occurred.',
                                        isError: true,
                                      );
                                    } finally {
                                      if (modalContext.mounted) {
                                        setModalState(
                                            () => isSubmitting = false);
                                      }
                                    }
                                  } else {
                                    if (tokenCtrl.text.trim().isEmpty) {
                                      _showPopupToast(
                                        'Please enter the reset token from your email.',
                                        isError: true,
                                      );
                                      return;
                                    }
                                    if (passCtrl.text.length < 8) {
                                      _showPopupToast(
                                        'Password must be at least 8 characters.',
                                        isError: true,
                                      );
                                      return;
                                    }
                                    if (passCtrl.text != confirmCtrl.text) {
                                      _showPopupToast(
                                        'Password confirmation does not match.',
                                        isError: true,
                                      );
                                      return;
                                    }

                                    setModalState(() => isSubmitting = true);
                                    try {
                                      final response = await ApiService
                                          .httpClient
                                          .post(
                                            Uri.parse(
                                                '${ApiConfig.baseUrl}/reset-password'),
                                            headers: {
                                              'Accept': 'application/json',
                                              'Content-Type':
                                                  'application/json',
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
                                        _showPopupToast(
                                          data['message']?.toString() ??
                                              'Password reset successfully! You may now sign in.',
                                          isError: false,
                                        );
                                      } else {
                                        _showPopupToast(
                                          data['message']?.toString() ??
                                              'Invalid or expired reset token.',
                                          isError: true,
                                        );
                                      }
                                    } catch (_) {
                                      _showPopupToast(
                                        'Network error occurred.',
                                        isError: true,
                                      );
                                    } finally {
                                      if (modalContext.mounted) {
                                        setModalState(
                                            () => isSubmitting = false);
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
                              : Text(
                                  codeSent
                                      ? 'Reset Password'
                                      : 'Send Reset Instructions',
                                ),
                        ),
                      ),
                      if (!codeSent)
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                setModalState(() => codeSent = true),
                            child: const Text(
                              'Already have a reset token?',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactWidth = screenWidth < 350;

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
                padding: EdgeInsets.fromLTRB(
                  isCompactWidth ? 16 : 24,
                  14,
                  isCompactWidth ? 16 : 24,
                  18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Welcome Back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
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
                        fontSize: 12,
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
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompactWidth ? 16 : 24,
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
                                          bottom: 20,
                                        ),
                                        child: Image.asset(
                                          'assets/pink-storkia-maximized.webp',
                                          height: 54,
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
                                    const SizedBox(height: 16),
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
                                    const SizedBox(height: 18),
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
                                                  Flexible(
                                                    child: Text(
                                                      'Sign In to Storkia',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
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
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
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
                                              'Create a Buyer Account \u2192',
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
                                      'By signing in, you agree to Storkia\u2019s official policies:',
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
                                          '\u2022',
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
                                          '\u2022',
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
