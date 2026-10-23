import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  final UserModel user;
  final String token;

  const HomeScreen({super.key, required this.user, required this.token});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storkia Buyer Portal'),
        backgroundColor: const Color(0xFF881337),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 72, color: Color(0xFF881337)),
              const SizedBox(height: 16),
              Text(
                'Welcome, ${user.firstName} ${user.lastName}!',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Role: ${user.role}',
                  style: TextStyle(color: Colors.grey.shade600)),
              Text('Email: ${user.email}',
                  style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              const Text(
                'You are connected to dev.storkia.shop via Laravel API.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
