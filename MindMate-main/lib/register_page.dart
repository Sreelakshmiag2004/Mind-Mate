import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'custom_snackbar.dart';
import 'core/network/api_exception.dart';
import 'data/repositories/auth_repository.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;

  // Helper function to check if user exists in Firestore by username
  Future<bool> _userExists(String email) async {
    String username = email.split('@')[0];
    var userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();
    return userDoc.exists;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _register() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    // Phase 7: the new FastAPI backend is now the source of truth for
    // account creation, and its own 409 already tells the user exactly
    // what they need to know (see backend/app/api/routes/auth.py) — so the
    // old Firestore `_userExists` pre-check no longer runs first here. It
    // would incorrectly block a fresh backend registration for someone who
    // already has a legacy Firebase-only account but has never registered
    // with the new backend, which the old check couldn't tell apart from a
    // genuine duplicate.
    try {
      await AuthRepository.instance.register(email: email, password: password, fullName: name);
    } on ApiException catch (e) {
      showCustomSnackBar(context, e.message, icon: Icons.error_outline);
      return;
    }

    // Legacy Firebase sign-up, preserved as-is and run best-effort after
    // the new backend registration succeeds, purely so screens that have
    // not yet been migrated off Firebase (Home, Journal, Vault, Favorites,
    // Settings) keep working during this transitional phase — see
    // PHASE7_API_INTEGRATION.md, section P. Falls back to signing in
    // rather than treating "email already in use" as a failure here: the
    // new backend account (the one this method is actually responsible
    // for) has already been created successfully by this point, and a
    // pre-existing legacy Firebase account for the same email is exactly
    // the transitional case this fallback exists for.
    try {
      UserCredential userCredential;
      try {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
        } else {
          rethrow;
        }
      }
      final user = userCredential.user;
      final username = email.split('@')[0];
      // merge: true — unlike the original plain `.set(...)`, this must not
      // clobber an existing legacy document's fields (e.g. onboarding
      // details already completed) when the fallback above signs in to a
      // pre-existing account rather than creating a fresh one.
      await FirebaseFirestore.instance.collection('users').doc(username).set({
        'uid': user?.uid ?? '',
        'email': email,
        'name': name,
        'provider': 'email',
        'comfortPerson': {
          'relation': null,
          'name': null,
          'customRelation': null,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Legacy Firebase registration failed after backend registration succeeded: $e');
    }

    if (!mounted) return;
    showCustomSnackBar(context, 'Registration successful!', icon: Icons.check_circle_outline);
    Navigator.pop(context); // Go back to login
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDE7EF),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Image.asset(
                'assets/logo.png',
                height: 80,
              ),
              const SizedBox(height: 8),
              // App Name
              const Text(
                'MINDMATE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 2,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 16),
              // Title
              const Text(
                'Your Safe Space Begins Here',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2D2D),
                ),
              ),
              const SizedBox(height: 8),
              // Subtitle
              const Text(
                "Every journey to peace begins with a single step. Let's take it together.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF7B7B7B),
                ),
              ),
              const SizedBox(height: 24),
              // Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Name
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Name',
                        prefixIcon: const Icon(Icons.person, color: Color(0xFFEA8C6E)),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Email
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: 'Email',
                        prefixIcon: const Icon(Icons.email, color: Color(0xFFEA8C6E)),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscureText,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock, color: Color(0xFFEA8C6E)),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureText = !_obscureText;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        // Matches the backend's RegisterRequest password
                        // policy exactly (app/schemas/auth.py): at least 8
                        // characters, at least one letter, at least one
                        // digit. The old 6-character-only rule would let a
                        // user submit a password the backend then rejects
                        // with a 422 anyway.
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 8) {
                          return 'Password must be at least 8 characters';
                        }
                        if (!RegExp(r'[A-Za-z]').hasMatch(value)) {
                          return 'Password must contain at least one letter';
                        }
                        if (!RegExp(r'[0-9]').hasMatch(value)) {
                          return 'Password must contain at least one digit';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Register Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA8C6E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Register',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Privacy note
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Color(0xFF7B7B7B)),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Your information is private and protected. \nWe\'re here for your peace of mind.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7B7B7B)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Divider with Or
              Row(
                children: [
                  const Expanded(child: Divider(thickness: 1, color: Color(0xFFE0B8A4))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('Or', style: TextStyle(color: Color(0xFF7B7B7B))),
                  ),
                  const Expanded(child: Divider(thickness: 1, color: Color(0xFFE0B8A4))),
                ],
              ),
              const SizedBox(height: 16),
              // Google Sign-In Button
              GestureDetector(
                onTap: () async {
                  try {
                    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
                    if (googleUser == null) {
                      // User cancelled the sign-in
                      return;
                    }
                    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
                    final credential = GoogleAuthProvider.credential(
                      accessToken: googleAuth.accessToken,
                      idToken: googleAuth.idToken,
                    );
                    UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
                    User? user = userCredential.user;
                    if (user != null) {
                      // Use centralized user existence check
                      bool exists = await _userExists(user.email!);
                      String username = user.email!.split('@')[0];
                      if (exists) {
                        showCustomSnackBar(context, 'User already exists, use Google sign in.', icon: Icons.info_outline);
                        return;
                      }
                      await FirebaseFirestore.instance.collection('users').doc(username).set({
                        'uid': user.uid,
                        'email': user.email ?? '',
                        'name': user.displayName ?? '',
                        'provider': 'google',
                        'comfortPerson': {
                          'relation': null,
                          'name': null,
                          'customRelation': null,
                        },
                      });
                      showCustomSnackBar(context, 'Google registration successful!', icon: Icons.check_circle_outline);
                      Navigator.pop(context); // Go back to login or home
                    }
                  } catch (e) {
                    showCustomSnackBar(context, 'Google sign-in failed: $e', icon: Icons.error_outline);
                  }
                },
                child: ClipOval(
                  child: Image.asset(
                    'assets/google.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Bottom navigation text
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Have an account ? ", style: TextStyle(color: Color(0xFF7B7B7B))),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Sign in',
                      style: TextStyle(
                        color: Color(0xFFEA8C6E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
} 