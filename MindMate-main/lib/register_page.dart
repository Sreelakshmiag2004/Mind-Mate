import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'custom_snackbar.dart';

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
    if (_formKey.currentState!.validate()) {
      String email = _emailController.text.trim();
      String username = email.split('@')[0];
      // Use centralized user existence check
      bool exists = await _userExists(email);
      if (exists) {
        showCustomSnackBar(context, 'Already User exists, so use sign in.', icon: Icons.info_outline);
        return;
      }
      try {
        // Try to register in Firebase Auth
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: _passwordController.text.trim(),
        );
        User? user = userCredential.user;
        // Only if registration succeeds, write to Firestore
        await FirebaseFirestore.instance.collection('users').doc(username).set({
          'uid': user?.uid ?? '',
          'email': email,
          'name': _nameController.text.trim(),
          'provider': 'email',
          'comfortPerson': {
            'relation': null,
            'name': null,
            'customRelation': null,
          },
        });
        showCustomSnackBar(context, 'Registration successful!', icon: Icons.check_circle_outline);
        Navigator.pop(context); // Go back to login
      } on FirebaseAuthException catch (e) {
        // Show error from Firebase Auth (e.g., email already in use)
        showCustomSnackBar(context, e.message ?? 'Registration failed', icon: Icons.error_outline);
      }
    }
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
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
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