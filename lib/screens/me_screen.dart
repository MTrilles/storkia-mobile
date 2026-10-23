import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import 'login_screen.dart'; // Imported LoginScreen

class MeScreen extends StatelessWidget {
  final UserModel user;
  final String token;

  const MeScreen({super.key, required this.user, required this.token});

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Color(0xFFCF4173)),
              SizedBox(width: 8),
              Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Are you sure you want to sign out of your account?',
            style: TextStyle(color: Color(0xFF292524), fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel',
                  style: TextStyle(
                      color: Color(0xFF78716C), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCF4173),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: () async {
                // 1. Close the confirmation dialog
                Navigator.of(dialogContext).pop();

                // 2. Show the loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext loadingContext) => const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFCF4173))),
                );

                // 3. Call the API
                await ApiService.logout(token);

                // 4. Safely handle navigation
                if (context.mounted) {
                  // Pop the loading indicator using rootNavigator to ensure it closes the dialog
                  Navigator.of(context, rootNavigator: true).pop();

                  // Navigate to LoginScreen using MaterialPageRoute instead of named route
                  Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                      (route) => false);
                }
              },
              child: const Text('Confirm',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuTile(
      {required IconData icon, required String title, VoidCallback? onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF6D8BD).withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFFCF4173), size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Color(0xFF292524),
        ),
      ),
      trailing:
          const Icon(Icons.chevron_right, color: Color(0xFFA8A29E), size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.only(
                  top: 24, bottom: 32, left: 24, right: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFCF4173), Color(0xFF5D3140)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white,
                    child: Text(
                      user.firstName.isNotEmpty
                          ? user.firstName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFCF4173),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${user.firstName} ${user.lastName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6D8BD).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            user.role,
                            style: const TextStyle(
                              color: Color(0xFFF6D8BD),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Shopping Activity',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF78716C).withOpacity(0.8),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              _buildSectionCard(
                children: [
                  _buildMenuTile(
                      icon: Icons.shopping_bag_outlined, title: 'My Orders'),
                  Divider(
                      height: 1,
                      color: Colors.grey.withOpacity(0.1),
                      indent: 64),
                  _buildMenuTile(
                      icon: Icons.favorite_border, title: 'Wish List'),
                  Divider(
                      height: 1,
                      color: Colors.grey.withOpacity(0.1),
                      indent: 64),
                  _buildMenuTile(icon: Icons.history, title: 'Recently Viewed'),
                  Divider(
                      height: 1,
                      color: Colors.grey.withOpacity(0.1),
                      indent: 64),
                  _buildMenuTile(
                      icon: Icons.storefront_outlined, title: 'Following'),
                ],
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Wallet & Rewards',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF78716C).withOpacity(0.8),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              _buildSectionCard(
                children: [
                  _buildMenuTile(
                      icon: Icons.local_offer_outlined, title: 'My Coupons'),
                  Divider(
                      height: 1,
                      color: Colors.grey.withOpacity(0.1),
                      indent: 64),
                  _buildMenuTile(
                      icon: Icons.monetization_on_outlined,
                      title: 'My Points/Coins'),
                ],
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Account Settings',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF78716C).withOpacity(0.8),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              _buildSectionCard(
                children: [
                  _buildMenuTile(
                      icon: Icons.manage_accounts_outlined,
                      title: 'Account Management'),
                  Divider(
                      height: 1,
                      color: Colors.grey.withOpacity(0.1),
                      indent: 64),
                  _buildMenuTile(icon: Icons.person_outline, title: 'Profile'),
                  Divider(
                      height: 1,
                      color: Colors.grey.withOpacity(0.1),
                      indent: 64),
                  _buildMenuTile(
                      icon: Icons.location_on_outlined, title: 'Address Book'),
                  Divider(
                      height: 1,
                      color: Colors.grey.withOpacity(0.1),
                      indent: 64),
                  _buildMenuTile(
                      icon: Icons.lock_outline, title: 'Change Password'),
                ],
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFCF4173),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: const Color(0xFFCF4173).withOpacity(0.3),
                          width: 1),
                    ),
                  ),
                  onPressed: () => _showLogoutDialog(context),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Log Out',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}
