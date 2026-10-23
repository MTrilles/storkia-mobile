import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const StorkiaMobileApp());
}

class StorkiaMobileApp extends StatelessWidget {
  const StorkiaMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Storkia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF881337),
          primary: const Color(0xFF881337),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      ),
      home: const SplashScreen(),
    );
  }
}
