import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'vault.dart';
import 'package:local_auth/local_auth.dart';
import 'custom_snackbar.dart';

class VaultPasswordPage extends StatefulWidget {
  const VaultPasswordPage({Key? key}) : super(key: key);

  @override
  State<VaultPasswordPage> createState() => _VaultPasswordPageState();
}

class _VaultPasswordPageState extends State<VaultPasswordPage> {
  bool _obscureText = true;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rePasswordController = TextEditingController();
  String? name;
  String? profileImageUrl;
  bool isLoading = true;
  bool isCreating = false; // true if creating password, false if authenticating
  String? vaultPasswordHash; // store hash from Firestore
  String? errorText;
  final LocalAuthentication auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _fetchName();
    _fetchProfileImage();
    _checkVaultPassword();
  }

  Future<void> _fetchName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      final username = user!.email!.split('@')[0];
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(username)
          .get();
      setState(() {
        name = doc.data()?['name'] ?? username;
      });
    } else {
      setState(() {
        name = 'User';
      });
    }
  }

  Future<void> _fetchProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email != null) {
        final username = user!.email!.split('@')[0];
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(username)
            .get();
        
        if (doc.exists && doc.data() != null) {
          setState(() {
            profileImageUrl = doc.data()!['profileImage'];
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
          });
        }
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _checkVaultPassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      final username = user!.email!.split('@')[0];
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(username)
          .get();
      setState(() {
        vaultPasswordHash = doc.data()?['vaultPasswordHash'];
        isCreating = vaultPasswordHash == null;
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Future<void> _createVaultPassword() async {
    setState(() { errorText = null; });
    final pass = _passwordController.text.trim();
    final rePass = _rePasswordController.text.trim();
    if (pass.isEmpty || rePass.isEmpty) {
      setState(() { errorText = 'Please fill both fields.'; });
      return;
    }
    if (pass.length < 6) {
      setState(() { errorText = 'Password must be at least 6 characters.'; });
      return;
    }
    if (pass != rePass) {
      setState(() { errorText = 'Passwords do not match.'; });
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      final username = user!.email!.split('@')[0];
      final hash = _hashPassword(pass);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(username)
          .set({'vaultPasswordHash': hash}, SetOptions(merge: true));
      await FirebaseFirestore.instance
          .collection('users')
          .doc(username)
          .set({'vaultPrevLastViewed': null, 'vaultLastViewed': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      setState(() {
        vaultPasswordHash = hash;
        isCreating = false;
        errorText = null;
        _passwordController.clear();
        _rePasswordController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault password created!')),
      );
    }
  }

  Future<void> _authenticateVaultPassword() async {
    setState(() { errorText = null; });
    final pass = _passwordController.text.trim();
    if (pass.isEmpty) {
      setState(() { errorText = 'Please enter your password.'; });
      return;
    }
    final hash = _hashPassword(pass);
    if (hash == vaultPasswordHash) {
      setState(() { errorText = null; });
      final username = FirebaseAuth.instance.currentUser!.email!.split('@')[0];
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(username)
          .get();
      final prev = userDoc.data()?['vaultLastViewed'];
      await FirebaseFirestore.instance
          .collection('users')
          .doc(username)
          .set({
            'vaultPrevLastViewed': prev,
            'vaultLastViewed': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault unlocked!')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => VaultPage()),
      );
    } else {
      setState(() { errorText = 'Incorrect password.'; });
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      bool isSupported = await auth.isDeviceSupported();
      bool canCheckBiometrics = await auth.canCheckBiometrics;
      if (!isSupported) {
        showCustomSnackBar(
          context,
          'Biometric hardware not available on this device.',
          icon: Icons.error_outline,
        );
        return;
      }
      if (!canCheckBiometrics) {
        showCustomSnackBar(
          context,
          'No biometrics enrolled. Please set up fingerprint/face unlock in your device settings.',
          icon: Icons.info_outline,
        );
        return;
      }
      bool isAuthenticated = await auth.authenticate(
        localizedReason: 'Unlock your vault with biometrics',
        options: const AuthenticationOptions(
          biometricOnly: true,
        ),
      );
      if (isAuthenticated) {
        final username = FirebaseAuth.instance.currentUser!.email!.split('@')[0];
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(username)
            .get();
        final prev = userDoc.data()?['vaultLastViewed'];
        await FirebaseFirestore.instance
            .collection('users')
            .doc(username)
            .set({
              'vaultPrevLastViewed': prev,
              'vaultLastViewed': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => VaultPage()),
        );
      } else {
        showCustomSnackBar(
          context,
          'Biometric authentication failed',
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      showCustomSnackBar(
        context,
        'Biometric authentication error: $e',
        icon: Icons.error_outline,
      );
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _rePasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD9D4),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            Center(
              child: isLoading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Title and subtitle
                          Row(
                            children: [
                              const Text(
                                'Vault',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFDCBB0),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Treasures of your heart,\nprotected here 💖',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          // Card
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Column(
                              children: [
                                // Panda user icon in a circle (centered at the top)
                                Center(
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD1A1A1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: ClipOval(
                                      child: profileImageUrl != null && profileImageUrl!.isNotEmpty
                                          ? Image.network(
                                              profileImageUrl!,
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Image.asset(
                                                  'assets/panda.png',
                                                  width: 56,
                                                  height: 56,
                                                  fit: BoxFit.cover,
                                                );
                                              },
                                            )
                                          : Image.asset(
                                              'assets/panda.png',
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Welcome text with Firestore name
                                Text.rich(
                                  TextSpan(
                                    text: 'Welcome Back ',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      color: Colors.black,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: name ?? 'User',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const TextSpan(text: ','),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (isCreating) ...[
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: _obscureText,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFFFE0F0),
                                      hintText: 'Enter Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: Color(0xFFB39DDB),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureText
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureText = !_obscureText;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        vertical: 0,
                                        horizontal: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _rePasswordController,
                                    obscureText: _obscureText,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFFFE0F0),
                                      hintText: 'Re Enter Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: Color(0xFFB39DDB),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureText
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureText = !_obscureText;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        vertical: 0,
                                        horizontal: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _createVaultPassword,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFDA8D7A),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(32),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'Create',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: _obscureText,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFFFE0F0),
                                      hintText: 'Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: Color(0xFFB39DDB),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureText
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureText = !_obscureText;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        vertical: 0,
                                        horizontal: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _authenticateVaultPassword,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFE19378),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(32),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'Unlock Now',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (errorText != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    errorText!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ],
                                // Privacy note
                                Row(
                                  children: [
                                    Transform.translate(
                                      offset: Offset(6, -8),
                                      child: Icon(
                                        Icons.lock,
                                        size: 20,
                                        color: Color(0xFFB0AEB1),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Your information is private and protected.\nYour secrets are safe here. We\'ve got your back',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF7B7B7B),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                // Fingerprint icon
                                IconButton(
                                  icon: Icon(Icons.fingerprint, size: 40),
                                  onPressed: _authenticateWithBiometrics,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      // Removed bottomNavigationBar
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool selected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 32,
          color: selected ? const Color(0xFFDA8D7A) : Colors.grey,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFFDA8D7A) : Colors.grey,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
