import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../models/user_model.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _currentStep = 1;

  // Step 1 Controllers
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _isLoading = false;
  int _resendCooldown = 0;
  Timer? _timer;

  // Step 2 Controllers
  final _formKeyStep2 = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _birthdayController = TextEditingController();
  String _selectedSex = 'male';

  // Step 3 Controllers
  final _formKeyStep3 = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;

  // Password Requirements
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

  void _startResendTimer() {
    setState(() => _resendCooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Please enter a valid email address.');
      return;
    }

    setState(() => _isLoading = true);
    final res = await ApiService.sendOtp(email);
    setState(() => _isLoading = false);

    if (res['success']) {
      setState(() => _codeSent = true);
      _startResendTimer();
    } else {
      _showError(res['message']);
    }
  }

  Future<void> _verifyOtp() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    if (code.length < 6) {
      _showError('Please enter the 6-digit code.');
      return;
    }

    setState(() => _isLoading = true);
    final res = await ApiService.verifyOtp(email, code);
    setState(() => _isLoading = false);

    if (res['success']) {
      setState(() => _currentStep = 2);
    } else {
      _showError(res['message']);
    }
  }

  void _goToPasswordStep() {
    if (_formKeyStep2.currentState!.validate()) {
      setState(() => _currentStep = 3);
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKeyStep3.currentState!.validate()) return;
    if (!_hasMinLength || !_hasUppercase || !_hasNumber || !_hasSpecial) {
      _showError('Please meet all password requirements.');
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
      password: _passwordController.text,
      passwordConfirmation: _confirmPasswordController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (res['success']) {
      final user = UserModel.fromJson(res['data']['user']);
      final token = res['data']['access_token'];

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (context) => HomeScreen(user: user, token: token)),
        (route) => false,
      );
    } else {
      _showError(res['message']);
    }
  }

  void _selectBirthday() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Color(0xFF881337)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Create an Account',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Serif',
                  color: Color(0xFF881337),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _currentStep == 1
                    ? 'Verify your email address to get started'
                    : _currentStep == 2
                        ? 'Tell us a little bit about yourself'
                        : 'Set up a secure password for your account',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildStepIndicator(),
              const SizedBox(height: 40),
              if (_currentStep == 1) _buildStep1(),
              if (_currentStep == 2) _buildStep2(),
              if (_currentStep == 3) _buildStep3(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [1, 2, 3].map((step) {
        final isActive = _currentStep == step;
        final isCompleted = _currentStep > step;
        return Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? const Color(0xFF881337)
                    : (isCompleted
                        ? const Color(0xFFFCE4EC)
                        : Colors.grey.shade200),
              ),
              alignment: Alignment.center,
              child: isCompleted
                  ? const Icon(Icons.check, size: 16, color: Color(0xFF881337))
                  : Text(
                      step.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : Colors.grey.shade500,
                      ),
                    ),
            ),
            if (step < 3)
              Container(
                width: 40,
                height: 2,
                color: isCompleted
                    ? const Color(0xFF881337).withOpacity(0.4)
                    : Colors.grey.shade300,
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
        TextField(
          controller: _emailController,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'EMAIL ADDRESS',
            labelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            hintText: 'name@example.com',
            border: const UnderlineInputBorder(),
            disabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade300)),
          ),
        ),
        const SizedBox(height: 24),
        if (!_codeSent)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF881337),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
                elevation: 0,
              ),
              onPressed: _isLoading ? null : _sendOtp,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Send Verification Code',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 16,
                    fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: 'VERIFICATION CODE',
                  labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0),
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Code sent to ${_emailController.text}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF881337),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _verifyOtp,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Verify & Continue',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed:
                      (_resendCooldown > 0 || _isLoading) ? null : _sendOtp,
                  child: Text(
                    _resendCooldown > 0
                        ? 'Resend available in ${_resendCooldown}s'
                        : 'Resend Code',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _resendCooldown > 0
                          ? Colors.grey
                          : const Color(0xFF881337),
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
                    labelText: 'FIRST NAME*',
                    labelStyle:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    border: UnderlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  onChanged: (v) => _formKeyStep2.currentState?.validate(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: _middleInitialController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 1,
                  decoration: const InputDecoration(
                    labelText: 'M.I.',
                    counterText: '',
                    labelStyle:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    border: UnderlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'LAST NAME*',
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              border: UnderlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
            onChanged: (v) => _formKeyStep2.currentState?.validate(),
          ),
          const SizedBox(height: 24),
          const Text('SEX*',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
          Row(
            children: [
              Radio<String>(
                value: 'male',
                groupValue: _selectedSex,
                activeColor: const Color(0xFF881337),
                onChanged: (val) => setState(() => _selectedSex = val!),
              ),
              const Text('Male',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(width: 24),
              Radio<String>(
                value: 'female',
                groupValue: _selectedSex,
                activeColor: const Color(0xFF881337),
                onChanged: (val) => setState(() => _selectedSex = val!),
              ),
              const Text('Female',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _birthdayController,
            readOnly: true,
            onTap: _selectBirthday,
            decoration: const InputDecoration(
              labelText: 'BIRTHDAY*',
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              hintText: 'YYYY-MM-DD',
              border: UnderlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today, size: 18),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF881337),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
                elevation: 0,
              ),
              onPressed: _goToPasswordStep,
              child: const Text('Continue',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
              labelText: 'PASSWORD*',
              labelStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              border: const UnderlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 18),
                onPressed: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              return null;
            },
            onChanged: (v) => _formKeyStep3.currentState?.validate(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: !_isConfirmVisible,
            decoration: InputDecoration(
              labelText: 'CONFIRM PASSWORD*',
              labelStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              border: const UnderlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _isConfirmVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18),
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
            onChanged: (v) => _formKeyStep3.currentState?.validate(),
          ),
          const SizedBox(height: 16),
          // Dynamic Requirements Indicator
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            childAspectRatio: 8,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildRequirementRow('8+ characters', _hasMinLength),
              _buildRequirementRow('1 uppercase', _hasUppercase),
              _buildRequirementRow('1 number', _hasNumber),
              _buildRequirementRow('1 special symbol', _hasSpecial),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _currentStep = 2),
                child: const Text('Back',
                    style: TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF881337),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25)),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _handleRegister,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Complete Registration',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementRow(String text, bool isMet) {
    return Row(
      children: [
        Icon(
          isMet ? Icons.check : Icons.circle,
          size: isMet ? 14 : 6,
          color: isMet ? Colors.green : Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isMet ? FontWeight.bold : FontWeight.normal,
            color: isMet ? Colors.green : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
