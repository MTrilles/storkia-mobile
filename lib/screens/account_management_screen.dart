import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/user_model.dart';

class AccountManagementScreen extends StatefulWidget {
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
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  late UserModel _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: const Color(0xFFE11D48)),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: const Color(0xFF10B981)),
    );
  }

  Future<void> _updateName() async {
    final firstController = TextEditingController(text: _currentUser.firstName);
    final lastController = TextEditingController(text: _currentUser.lastName);
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Name',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstController,
                decoration: const InputDecoration(
                    labelText: 'First Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastController,
                decoration: const InputDecoration(
                    labelText: 'Last Name', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF78716C))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCF4173)),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setState(() => isSubmitting = true);
                      try {
                        final response = await http.patch(
                          Uri.parse('${widget.baseUrl}/api/v1/account/name'),
                          headers: {
                            'Authorization': 'Bearer ${widget.token}',
                            'Accept': 'application/json',
                            'Content-Type': 'application/json',
                          },
                          body: json.encode({
                            'first_name': firstController.text.trim(),
                            'last_name': lastController.text.trim(),
                          }),
                        );
                        final data = json.decode(response.body);
                        if (response.statusCode == 200 && data['success']) {
                          this.setState(() =>
                              _currentUser = UserModel.fromJson(data['data']));
                          _showSuccess(data['message']);
                          if (mounted) Navigator.pop(context);
                        } else {
                          _showError(data['message'] ?? 'Update failed.');
                        }
                      } catch (e) {
                        _showError('Network error.');
                      } finally {
                        setState(() => isSubmitting = false);
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updatePhone() async {
    final phoneController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Phone Number',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixText: '+63 ',
              border: OutlineInputBorder(),
              hintText: '9xxxxxxxxx',
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF78716C))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCF4173)),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setState(() => isSubmitting = true);
                      try {
                        final response = await http.patch(
                          Uri.parse('${widget.baseUrl}/api/v1/account/phone'),
                          headers: {
                            'Authorization': 'Bearer ${widget.token}',
                            'Accept': 'application/json',
                            'Content-Type': 'application/json',
                          },
                          body: json.encode(
                              {'contact_no': phoneController.text.trim()}),
                        );
                        final data = json.decode(response.body);
                        if (response.statusCode == 200 && data['success']) {
                          this.setState(() =>
                              _currentUser = UserModel.fromJson(data['data']));
                          _showSuccess(data['message']);
                          if (mounted) Navigator.pop(context);
                        } else {
                          _showError(data['message'] ?? 'Update failed.');
                        }
                      } catch (e) {
                        _showError('Network error.');
                      } finally {
                        setState(() => isSubmitting = false);
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateEmailFlow() async {
    final emailController = TextEditingController();
    final otpController = TextEditingController();
    int step = 1; // 1: Input Email, 2: Input OTP
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(step == 1 ? 'Change Email' : 'Verify OTP',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (step == 1) ...[
                const Text(
                    'Enter your new email address to receive a verification code.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF78716C))),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'New Email', border: OutlineInputBorder()),
                ),
              ] else ...[
                const Text('Enter the 6-digit code sent to your new email.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF78716C))),
                const SizedBox(height: 12),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  decoration: const InputDecoration(
                      labelText: 'OTP Code', border: OutlineInputBorder()),
                ),
              ]
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF78716C))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCF4173)),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setState(() => isSubmitting = true);
                      try {
                        if (step == 1) {
                          final response = await http.post(
                            Uri.parse(
                                '${widget.baseUrl}/api/v1/account/email/request-otp'),
                            headers: {
                              'Authorization': 'Bearer ${widget.token}',
                              'Accept': 'application/json',
                              'Content-Type': 'application/json',
                            },
                            body: json
                                .encode({'email': emailController.text.trim()}),
                          );
                          final data = json.decode(response.body);
                          if (response.statusCode == 200 && data['success']) {
                            setState(() => step = 2);
                            _showSuccess(data['message']);
                          } else {
                            _showError(
                                data['message'] ?? 'Failed to send OTP.');
                          }
                        } else {
                          final response = await http.post(
                            Uri.parse(
                                '${widget.baseUrl}/api/v1/account/email/verify-otp'),
                            headers: {
                              'Authorization': 'Bearer ${widget.token}',
                              'Accept': 'application/json',
                              'Content-Type': 'application/json',
                            },
                            body: json
                                .encode({'code': otpController.text.trim()}),
                          );
                          final data = json.decode(response.body);
                          if (response.statusCode == 200 && data['success']) {
                            this.setState(() => _currentUser =
                                UserModel.fromJson(data['data']));
                            _showSuccess(data['message']);
                            if (mounted) Navigator.pop(context);
                          } else {
                            _showError(data['message'] ?? 'Invalid OTP.');
                          }
                        }
                      } catch (e) {
                        _showError('Network error.');
                      } finally {
                        setState(() => isSubmitting = false);
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(step == 1 ? 'Send OTP' : 'Verify & Save',
                      style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updatePasswordFlow() async {
    int step = 0; // 0: Start, 1: Verify OTP, 2: New Password
    bool isSubmitting = false;
    String unlockToken = '';
    final otpController = TextEditingController();
    final pwdController = TextEditingController();
    final confirmPwdController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void triggerRequestOtp() async {
            setState(() => isSubmitting = true);
            try {
              final response = await http.post(
                Uri.parse(
                    '${widget.baseUrl}/api/v1/account/password/request-otp'),
                headers: {
                  'Authorization': 'Bearer ${widget.token}',
                  'Accept': 'application/json'
                },
              );
              final data = json.decode(response.body);
              if (response.statusCode == 200 && data['success']) {
                setState(() => step = 1);
                _showSuccess(data['message']);
              } else {
                _showError(data['message'] ?? 'Failed to send OTP.');
              }
            } catch (e) {
              _showError('Network error.');
            } finally {
              setState(() => isSubmitting = false);
            }
          }

          if (step == 0 && !isSubmitting) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => triggerRequestOtp());
          }

          return AlertDialog(
            title: Text(
                step == 1
                    ? 'Verify Identity'
                    : (step == 2 ? 'New Password' : 'Processing'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (step == 0)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child:
                          CircularProgressIndicator(color: Color(0xFFCF4173)))
                else if (step == 1) ...[
                  const Text(
                      'Enter the 6-digit code sent to your current email.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF78716C))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    decoration: const InputDecoration(
                        labelText: 'OTP Code', border: OutlineInputBorder()),
                  ),
                ] else if (step == 2) ...[
                  TextField(
                    controller: pwdController,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'New Password',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPwdController,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Must contain 8+ characters, uppercase, number, and special character.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF78716C))),
                ]
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF78716C))),
              ),
              if (step > 0)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCF4173)),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setState(() => isSubmitting = true);
                          try {
                            if (step == 1) {
                              final response = await http.post(
                                Uri.parse(
                                    '${widget.baseUrl}/api/v1/account/password/verify-otp'),
                                headers: {
                                  'Authorization': 'Bearer ${widget.token}',
                                  'Accept': 'application/json',
                                  'Content-Type': 'application/json',
                                },
                                body: json.encode(
                                    {'code': otpController.text.trim()}),
                              );
                              final data = json.decode(response.body);
                              if (response.statusCode == 200 &&
                                  data['success']) {
                                unlockToken = data['unlock_token'];
                                setState(() => step = 2);
                              } else {
                                _showError(data['message'] ?? 'Invalid OTP.');
                              }
                            } else if (step == 2) {
                              final response = await http.patch(
                                Uri.parse(
                                    '${widget.baseUrl}/api/v1/account/password'),
                                headers: {
                                  'Authorization': 'Bearer ${widget.token}',
                                  'Accept': 'application/json',
                                  'Content-Type': 'application/json',
                                },
                                body: json.encode({
                                  'unlock_token': unlockToken,
                                  'password': pwdController.text,
                                  'password_confirmation':
                                      confirmPwdController.text,
                                }),
                              );
                              final data = json.decode(response.body);
                              if (response.statusCode == 200 &&
                                  data['success']) {
                                _showSuccess(data['message']);
                                if (mounted) Navigator.pop(context);
                              } else {
                                _showError(data['message'] ??
                                    'Password update failed.');
                              }
                            }
                          } catch (e) {
                            _showError('Network error.');
                          } finally {
                            setState(() => isSubmitting = false);
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(step == 1 ? 'Verify' : 'Save Password',
                          style: const TextStyle(color: Colors.white)),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF292524),
        elevation: 0.5,
        title: const Text('Account Management',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: const Color(0xFFCF4173).withOpacity(0.1),
                  child: Text(
                    _currentUser.firstName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFCF4173)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Tap to change photo',
                    style: TextStyle(fontSize: 12, color: Color(0xFF78716C))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                _buildOptionTile(
                    'Name',
                    '${_currentUser.firstName} ${_currentUser.lastName}',
                    _updateName),
                const Divider(height: 1, indent: 16),
                _buildOptionTile(
                    'Phone',
                    _currentUser.role == 'Buyer' ? 'Add Phone' : 'Hidden',
                    _updatePhone), // Fallback if no phone field on UserModel
                const Divider(height: 1, indent: 16),
                _buildOptionTile('Email', _currentUser.email, _updateEmailFlow),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            child: _buildOptionTile(
                'Change Password', '********', _updatePasswordFlow),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(String label, String value, VoidCallback onTap) {
    return ListTile(
      title: Text(label,
          style: const TextStyle(fontSize: 14, color: Color(0xFF292524))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(fontSize: 14, color: Color(0xFF78716C))),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }
}
