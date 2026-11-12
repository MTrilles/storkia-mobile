import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/global_counters_provider.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

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

    setState(() => _isLoading = true);
    final res = await ApiService.sendOtp(email);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
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

    setState(() => _isLoading = true);
    final res = await ApiService.verifyOtp(email, code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
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
    if (picked != null) {
      setState(() {
        _birthdayController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
      _formKeyStep2.currentState?.validate();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: StorkTheme.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Create Buyer Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  _buildStepIndicator(),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: StorkTheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: StorkTheme.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentStep == 1
                              ? 'Verify Your Email'
                              : _currentStep == 2
                                  ? 'Personal Information'
                                  : 'Create a Secure Password',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final labels = ['Email OTP', 'Profile', 'Password'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [1, 2, 3].map((step) {
        final isActive = _currentStep == step;
        final isCompleted = _currentStep > step;

        return Row(
          children: [
            Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? StorkTheme.primary
                        : (isCompleted
                            ? StorkTheme.primary.withValues(alpha: 0.15)
                            : StorkTheme.borderSubtle),
                  ),
                  alignment: Alignment.center,
                  child: isCompleted
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: StorkTheme.primary)
                      : Text(
                          step.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color:
                                isActive ? Colors.white : StorkTheme.textMuted,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[step - 1],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? StorkTheme.primary : StorkTheme.textMuted,
                  ),
                ),
              ],
            ),
            if (step < 3)
              Container(
                width: 48,
                height: 2,
                margin: const EdgeInsets.only(bottom: 16, left: 8, right: 8),
                color: isCompleted
                    ? StorkTheme.primary.withValues(alpha: 0.5)
                    : StorkTheme.borderSubtle,
              ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EMAIL ADDRESS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: StorkTheme.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'name@example.com',
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
            height: 48,
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
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: StorkTheme.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 12,
                  fontWeight: FontWeight.w800,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '000000',
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
                height: 48,
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
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _firstNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'First Name*',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!RegExp(r'^[A-Za-z\s]+$').hasMatch(v.trim())) {
                      return 'Letters only';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: _middleInitialController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 1,
                  decoration: const InputDecoration(
                    labelText: 'M.I.',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _lastNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Last Name*',
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
            'SEX*',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: StorkTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedSex = 'male'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: _selectedSex == 'male'
                          ? StorkTheme.primary.withValues(alpha: 0.1)
                          : StorkTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedSex == 'male'
                            ? StorkTheme.primary
                            : StorkTheme.borderSubtle,
                        width: _selectedSex == 'male' ? 1.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Male',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
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
                  onTap: () => setState(() => _selectedSex = 'female'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: _selectedSex == 'female'
                          ? StorkTheme.primary.withValues(alpha: 0.1)
                          : StorkTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedSex == 'female'
                            ? StorkTheme.primary
                            : StorkTheme.borderSubtle,
                        width: _selectedSex == 'female' ? 1.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Female',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
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
              labelText: 'Date of Birth (18+)*',
              hintText: 'YYYY-MM-DD',
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
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
              labelText: 'Password*',
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
              labelText: 'Confirm Password*',
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
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildRequirementChip('8+ characters', _hasMinLength),
              _buildRequirementChip('1 uppercase', _hasUppercase),
              _buildRequirementChip('1 number', _hasNumber),
              _buildRequirementChip('1 special symbol', _hasSpecial),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _currentStep = 2),
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
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
                        : const Text('Complete Registration'),
                  ),
                ),
              ),
            ],
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
