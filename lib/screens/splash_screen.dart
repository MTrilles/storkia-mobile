import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/global_counters_provider.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapSession();
    });
  }

  Future<void> _bootstrapSession() async {
    final hasSession = await ref.read(authProvider.notifier).restoreSession();
    if (!mounted) return;

    final authState = ref.read(authProvider);
    if (hasSession && authState.user != null && authState.token != null) {
      final token = authState.token!;
      ref.read(cartCountProvider.notifier).fetchCartCount(token);
      ref.read(unreadMessageProvider.notifier).fetchUnreadCount(token);
      ref.read(unreadNotificationProvider.notifier).fetchUnreadCount(token);

      Navigator.of(context).pushReplacement(
        StorkRoute.fade(
          HomeScreen(user: authState.user!, token: token),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        StorkRoute.fade(const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/pink-storkia-maximized.webp',
              width: 190,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: StorkTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
