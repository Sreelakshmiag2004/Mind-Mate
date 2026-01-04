import 'package:flutter/material.dart';
import 'edit_profile_page.dart';
import 'notifications_settings_page.dart';
import 'help.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'custom_snackbar.dart';
import 'about_us.dart';
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDD5D1),
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 60),
                const SizedBox(height: 32),
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _SettingsOption(
                        icon: Icons.edit,
                        label: 'Edit profile',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditProfilePage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _SettingsOption(
                        icon: Icons.phonelink_lock,
                        label: 'Change password',
                        onTap: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) return;
                          final username = user.email?.split('@')[0];
                          if (username == null) return;
                          final userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();
                          final provider = userDoc.data()?['provider'] ?? 'email';
                          if (provider == 'google') {
                            showCustomSnackBar(
                              context,
                              'Password change is not available for Google sign-in accounts.',
                              icon: Icons.info_outline,
                            );
                            return;
                          }
                          try {
                            await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
                            showCustomSnackBar(
                              context,
                              'Password reset email sent!',
                              icon: Icons.check_circle_outline,
                            );
                          } catch (e) {
                            showCustomSnackBar(
                              context,
                              'Failed to send reset email: \\$e',
                              icon: Icons.error_outline,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      _SettingsOption(
                        icon: Icons.notifications,
                        label: 'Notification settings',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NotificationSettingsPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _SettingsOption(
                        icon: Icons.groups,
                        label: 'About us',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => AboutUsPage()),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _SettingsOption(
                        icon: Icons.info,
                        label: 'Help',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => HelpPage()),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _SettingsOption(
                        icon: Icons.notifications,
                        label: 'Logout',
                        onTap: () async {
                          await FirebaseAuth.instance.signOut();
                          Navigator.pushReplacementNamed(context, '/');
                        },
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Color(0xFF7B7B7B),
                          ),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Your information is private and protected. Your secrets are safe here. We\'ve got your back',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7B7B7B),
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsOption({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Color(0xFFEA8C6E), width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: Color(0xFFEA8C6E), size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
