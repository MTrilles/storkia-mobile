import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/global_counters_provider.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'legal_policies_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  int _currentStep = 1;

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  String? _verificationToken;
  bool _codeSent = false;
  bool _isLoading = false;
  int _resendCooldown = 0;
  Timer? _timer;

  final _formKeyStep2 = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _birthdayController = TextEditingController();
  String _selectedSex = 'male';

  final _formKeyStep3 = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;
  bool _agreedToPolicies = true;

  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updatePasswordRequirements);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleInitialController.dispose();
    _birthdayController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updatePasswordRequirements() {
    final pass = _passwordController.text;
    setState(() {
      _hasMinLength = pass.length >= 8;
      _hasUppercase = pass.contains(RegExp(r'[A-Z]'));
      _hasNumber = pass.contains(RegExp(r'[0-9]'));
      _hasSpecial = pass.contains(RegExp(r'[\W_]'));
    });
  }

  void _startResendTimer([int seconds = 60]) {
    _timer?.cancel();
    setState(() => _resendCooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Please enter a valid email address.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);
    final res = await ApiService.sendOtp(email);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      HapticFeedback.mediumImpact();
      setState(() => _codeSent = true);
      _startResendTimer(res['cooldown'] ?? 60);
    } else {
      final int cooldown = res['cooldown'] ?? 0;
      if (cooldown > 0) {
        setState(() => _codeSent = true);
        _startResendTimer(cooldown);
      }
      _showError(res['message'] ?? 'Could not send verification code.');
    }
  }

  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (code.length < 6) {
      _showError('Please enter the 6-digit verification code.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);
    final res = await ApiService.verifyOtp(email, code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      HapticFeedback.mediumImpact();
      setState(() {
        _verificationToken = res['verification_token']?.toString();
        _currentStep = 2;
      });
    } else {
      _showError(res['message'] ?? 'Invalid verification code.');
    }
  }

  void _goToPasswordStep() {
    FocusScope.of(context).unfocus();
    if (_formKeyStep2.currentState!.validate()) {
      HapticFeedback.selectionClick();
      setState(() => _currentStep = 3);
    }
  }

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();
    if (!_formKeyStep3.currentState!.validate()) return;
    if (!_hasMinLength || !_hasUppercase || !_hasNumber || !_hasSpecial) {
      _showError('Please meet all password security requirements.');
      return;
    }
    if (!_agreedToPolicies) {
      _showError(
          'Please agree to the Storkia Terms & Conditions and Privacy Policy.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);
    final res = await ApiService.register(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      middleInitial: _middleInitialController.text.trim().isEmpty
          ? null
          : _middleInitialController.text.trim(),
      sex: _selectedSex,
      birthday: _birthdayController.text,
      email: _emailController.text.trim(),
      verificationToken: _verificationToken,
      password: _passwordController.text,
      passwordConfirmation: _confirmPasswordController.text,
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
      Navigator.pushAndRemoveUntil(
        context,
        StorkRoute.fade(HomeScreen(user: user, token: token)),
        (route) => false,
      );
    } else {
      _showError(res['message'] ?? 'Registration failed.');
    }
  }

  Future<void> _selectBirthday() async {
    final DateTime eighteenYearsAgo =
        DateTime.now().subtract(const Duration(days: 365 * 18 + 4));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: eighteenYearsAgo,
      firstDate: DateTime(1925),
      lastDate: eighteenYearsAgo,
    );
    if (picked != null && mounted) {
      HapticFeedback.selectionClick();
      setState(() {
        _birthdayController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
      _formKeyStep2.currentState?.validate();
    }
  }

  void _openPolicyTab(int tabIndex) {
    Navigator.push(
      context,
      StorkRoute.fade(LegalPoliciesScreen(initialTab: tabIndex)),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: StorkTheme.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompactWidth = MediaQuery.sizeOf(context).width < 350;

    return Scaffold(
      backgroundColor: StorkTheme.surface,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: StorkTheme.brandGradient,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompactWidth ? 12 : 16,
                  8,
                  isCompactWidth ? 12 : 16,
                  20,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Create Buyer Account',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildStepIndicator(),
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
                      vertical: 22,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - 44)
                            .clamp(0.0, double.infinity),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentStep == 1
                                        ? 'Verify Your Email'
                                        : _currentStep == 2
                                            ? 'Personal Information'
                                            : 'Create a Secure Password',
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      color: StorkTheme.primaryDark,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _currentStep == 1
                                        ? 'We will send a 6-digit verification code to your email.'
                                        : _currentStep == 2
                                            ? 'Please enter your legal name and date of birth.'
                                            : 'Choose a strong password for your Storkia account.',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: StorkTheme.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  if (_currentStep == 1) _buildStep1(),
                                  if (_currentStep == 2) _buildStep2(),
                                  if (_currentStep == 3) _buildStep3(),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 28),
                                child: _buildLegalFooterLinks(),
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

  Widget _buildLegalFooterLinks() {
    Widget link(String label, int tab) {
      return InkWell(
        onTap: () => _openPolicyTab(tab),
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

    return Column(
      children: [
        const Divider(height: 1),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 2,
          children: [
            link('Terms & Conditions', 0),
            const Text('\u2022', style: TextStyle(color: StorkTheme.textMuted)),
            link('Privacy Policy', 1),
            const Text('\u2022', style: TextStyle(color: StorkTheme.textMuted)),
            link('Cookie Policy', 2),
          ],
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    final labels = ['Email OTP', 'Profile', 'Password'];
    return Row(
      children: [
        for (int step = 1; step <= 3; step++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentStep == step
                        ? Colors.white
                        : (_currentStep > step
                            ? StorkTheme.brandLight
                            : Colors.white.withValues(alpha: 0.2)),
                  ),
                  alignment: Alignment.center,
                  child: _currentStep > step
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: StorkTheme.primaryDark,
                        )
                      : Text(
                          step.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: _currentStep == step
                                ? StorkTheme.primaryDark
                                : Colors.white,
                          ),
                        ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    labels[step - 1],
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _currentStep == step
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: _currentStep == step
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (step < 3)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 18),
                color: _currentStep > step
                    ? StorkTheme.brandLight
                    : Colors.white.withValues(alpha: 0.25),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildStep1() {
    final isNarrow = MediaQuery.sizeOf(context).width < 350;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EMAIL ADDRESS',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: StorkTheme.primaryDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'name@example.com',
            fillColor: StorkTheme.surfaceSubtle,
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            suffixIcon: _codeSent
                ? TextButton(
                    onPressed: () {
                      setState(() {
                        _codeSent = false;
                        _codeController.clear();
                      });
                    },
                    child: const Text('Change', style: TextStyle(fontSize: 12)),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 20),
        if (!_codeSent)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOtp,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Send Verification Code'),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '6-DIGIT VERIFICATION CODE',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: StorkTheme.primaryDark,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                maxLength: 6,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isNarrow ? 19 : 22,
                  letterSpacing: isNarrow ? 7 : 12,
                  fontWeight: FontWeight.w800,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  fillColor: StorkTheme.surfaceSubtle,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Code sent to ${_emailController.text.trim()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: StorkTheme.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Verify & Continue'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed:
                      (_resendCooldown > 0 || _isLoading) ? null : _sendOtp,
                  child: Text(
                    _resendCooldown > 0
                        ? 'Resend code in ${_resendCooldown}s'
                        : 'Resend Verification Code',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _resendCooldown > 0
                          ? StorkTheme.textMuted
                          : StorkTheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStep2() {
    return Form(
      key: _formKeyStep2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final firstField = TextFormField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'First Name *',
                  fillColor: StorkTheme.surfaceSubtle,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!RegExp(r'^[A-Za-z\s]+$').hasMatch(v.trim())) {
                    return 'Letters only';
                  }
                  return null;
                },
              );
              final miField = TextFormField(
                controller: _middleInitialController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 1,
                decoration: const InputDecoration(
                  labelText: 'M.I.',
                  counterText: '',
                  fillColor: StorkTheme.surfaceSubtle,
                ),
              );

              if (constraints.maxWidth < 290) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    firstField,
                    const SizedBox(height: 12),
                    miField,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: firstField),
                  const SizedBox(width: 10),
                  Expanded(flex: 1, child: miField),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _lastNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Last Name *',
              fillColor: StorkTheme.surfaceSubtle,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (!RegExp(r'^[A-Za-z\s]+$').hasMatch(v.trim())) {
                return 'Letters only';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'SEX *',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedSex = 'male');
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedSex == 'male'
                          ? StorkTheme.primary.withValues(alpha: 0.1)
                          : StorkTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _selectedSex == 'male'
                            ? StorkTheme.primary
                            : StorkTheme.borderSubtle,
                        width: _selectedSex == 'male' ? 1.6 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Male',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _selectedSex == 'male'
                            ? StorkTheme.primary
                            : StorkTheme.textMain,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedSex = 'female');
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedSex == 'female'
                          ? StorkTheme.primary.withValues(alpha: 0.1)
                          : StorkTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _selectedSex == 'female'
                            ? StorkTheme.primary
                            : StorkTheme.borderSubtle,
                        width: _selectedSex == 'female' ? 1.6 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Female',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _selectedSex == 'female'
                            ? StorkTheme.primary
                            : StorkTheme.textMain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _birthdayController,
            readOnly: true,
            onTap: _selectBirthday,
            decoration: const InputDecoration(
              labelText: 'Date of Birth (18+) *',
              hintText: 'YYYY-MM-DD',
              fillColor: StorkTheme.surfaceSubtle,
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _goToPasswordStep,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Form(
      key: _formKeyStep3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            decoration: InputDecoration(
              labelText: 'Password *',
              fillColor: StorkTheme.surfaceSubtle,
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: !_isConfirmVisible,
            decoration: InputDecoration(
              labelText: 'Confirm Password *',
              fillColor: StorkTheme.surfaceSubtle,
              prefixIcon: const Icon(Icons.verified_user_outlined, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _isConfirmVisible
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _isConfirmVisible = !_isConfirmVisible),
              ),
            ),
            validator: (v) {
              if (v != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildRequirementChip('8+ characters', _hasMinLength),
              _buildRequirementChip('1 uppercase', _hasUppercase),
              _buildRequirementChip('1 number', _hasNumber),
              _buildRequirementChip('1 special symbol', _hasSpecial),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: StorkTheme.surfaceSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: StorkTheme.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _agreedToPolicies,
                    activeColor: StorkTheme.primary,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() => _agreedToPolicies = val ?? false);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 12,
                        color: StorkTheme.textMain,
                        height: 1.38,
                      ),
                      children: [
                        const TextSpan(text: 'I have read and agree to the '),
                        TextSpan(
                          text: 'Terms & Conditions',
                          style: const TextStyle(
                            color: StorkTheme.primary,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _openPolicyTab(0),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: const TextStyle(
                            color: StorkTheme.primary,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _openPolicyTab(1),
                        ),
                        const TextSpan(text: ' of Storkia.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final backBtn = OutlinedButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _currentStep = 2);
                },
                child: const Text('Back'),
              );
              final submitBtn = SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Complete Registration',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              );

              if (constraints.maxWidth < 310) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    submitBtn,
                    const SizedBox(height: 8),
                    backBtn,
                  ],
                );
              }

              return Row(
                children: [
                  backBtn,
                  const SizedBox(width: 12),
                  Expanded(child: submitBtn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementChip(String text, bool isMet) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isMet
            ? StorkTheme.success.withValues(alpha: 0.1)
            : StorkTheme.surfaceSubtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isMet
              ? StorkTheme.success.withValues(alpha: 0.3)
              : StorkTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMet ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: isMet ? StorkTheme.success : StorkTheme.textMuted,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isMet ? FontWeight.w700 : FontWeight.w500,
              color: isMet ? StorkTheme.success : StorkTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
