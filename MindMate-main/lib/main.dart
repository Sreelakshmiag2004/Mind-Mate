import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_page.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'regfav.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'custom_snackbar.dart';
import 'enter_details_page.dart';
import 'shoutout_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'duration_adapter.dart';
import 'vault.dart';
import 'image_note.dart';
import 'video_note.dart';
import 'package:path_provider/path_provider.dart';
import 'homepage.dart';
import 'core/network/api_exception.dart';
import 'data/repositories/auth_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Hive.initFlutter();
  Hive.registerAdapter(DurationAdapter());
  Hive.registerAdapter(VoiceNoteAdapter());
  Hive.registerAdapter(ImageNoteAdapter());
  Hive.registerAdapter(VideoNoteAdapter());
  await Hive.openBox<VoiceNote>('voice_notes');
  await Hive.openBox<ImageNote>('image_notes');
  await Hive.openBox<VideoNote>('video_notes');
  await Hive.openBox('schedulerBox');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Login Page',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashScreen(),
      initialRoute: null,
      routes: {
        '/enterDetails': (context) => EnterDetailsPage(),
        '/selectFavPerson': (context) => RegFavPage(),
        '/shoutout': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map;
          return ShoutoutPage(
            title: args['title'],
            description: args['description'],
            dateKey: args['dateKey'],
            userId: args['userId'],
          );
        },
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    await Future.delayed(
      const Duration(milliseconds: 500),
    ); // for splash effect

    // Phase 7: restore the new FastAPI session (if one is stored) so
    // AuthRepository/ApiClient have a valid access token ready before any
    // future FastAPI-backed screen needs one. Deliberately best-effort and
    // non-blocking for navigation: which screen the splash routes to is
    // still decided entirely by the existing Firebase-based logic below,
    // unchanged (see PHASE7_API_INTEGRATION.md, section O, for why the two
    // are kept independent during this transitional phase — journals,
    // mood, checklist, etc. are still Firebase-backed and out of scope
    // here). A failed restore (no session, or a network hiccup) is not
    // treated as a reason to interrupt the existing flow.
    try {
      await AuthRepository.instance.restoreSession();
    } catch (_) {
      // Intentionally swallowed — see comment above.
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
      return;
    }
    final username = user.email?.split('@')[0];
    if (username == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
      return;
    }
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(username)
        .get();
    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data()!;
      if (data['name'] != null &&
          data['ageGroup'] != null &&
          data['phone'] != null &&
          data['city'] != null &&
          data['country'] != null) {
        // Check if comfort person is selected
        if (data['comfortPerson'] != null && data['comfortPerson']['relation'] != null) {
          // All details and comfort person are set, go to home
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        } else {
          // Details are present, but comfort person is not. Go to RegFavPage.
          Navigator.pushReplacementNamed(context, '/selectFavPerson');
        }
      } else {
        // Basic details are missing, go to EnterDetailsPage
        Navigator.pushReplacementNamed(context, '/enterDetails');
      }
    } else {
      // User exists in Auth but not Firestore, or other error
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFDE7EF),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;

  // Helper function to check if user exists in Firestore by username
  Future<bool> _userExists(String email) async {
    String username = email.split('@')[0];
    var userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(username)
        .get();
    return userDoc.exists;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Phase 7: the new FastAPI backend is the source of truth for
    // authentication going forward. `POST /auth/login` gives one identical
    // 401 for both "unknown email" and "wrong password" (see
    // backend/app/api/routes/auth.py — deliberate, to avoid letting this
    // call be used to enumerate registered emails), so the old
    // Firestore `_userExists` pre-check above is no longer run here: it
    // would incorrectly block a legacy Firebase-only account that has
    // never registered with the new backend from ever logging in, and the
    // backend's own error already tells the user what they need to know.
    try {
      await AuthRepository.instance.login(email: email, password: password);
    } on ApiException catch (e) {
      showCustomSnackBar(context, e.message, icon: Icons.error_outline);
      return;
    }

    // Legacy Firebase sign-in, preserved as-is and run best-effort after
    // the new backend login succeeds, purely so screens that have not yet
    // been migrated off Firebase (Home, Journal, Vault, Favorites,
    // Settings — see PHASE6_INTEGRATION_AUDIT.md) keep working during this
    // transitional phase. Its own failure is intentionally non-fatal here:
    // the new backend session (the one this phase is responsible for) has
    // already succeeded, and swallowing this matches how every other
    // legacy Firebase call in this file already handles its own errors
    // independently, per screen. See PHASE7_API_INTEGRATION.md, section P.
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      debugPrint('Legacy Firebase sign-in failed after backend login succeeded: $e');
    }

    // Existing navigation logic — UNCHANGED.
    String username = email.split('@')[0];
    var userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(username)
        .get();
    if (!mounted) return;
    if (userDoc.exists &&
        userDoc.data() != null &&
        userDoc.data()!['name'] != null &&
        userDoc.data()!['ageGroup'] != null &&
        userDoc.data()!['phone'] != null &&
        userDoc.data()!['city'] != null &&
        userDoc.data()!['country'] != null) {
      // Details exist, skip EnterDetailsPage
      Navigator.pushReplacementNamed(context, '/selectFavPerson');
    } else {
      // Details missing, go to EnterDetailsPage
      Navigator.pushReplacementNamed(context, '/enterDetails');
    }
  }

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut(); // Always show account picker
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in
        return;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      User? user = userCredential.user;
      if (user != null) {
        // Use centralized user existence check
        bool exists = await _userExists(user.email!);
        if (!exists) {
          showCustomSnackBar(
            context,
            'User not found, please register.',
            icon: Icons.info_outline,
          );
          return;
        }
        // Check if user details exist in Firestore
        String username = user.email!.split('@')[0];
        var userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(username)
            .get();
        if (userDoc.exists &&
            userDoc.data() != null &&
            userDoc.data()!['name'] != null &&
            userDoc.data()!['ageGroup'] != null &&
            userDoc.data()!['phone'] != null &&
            userDoc.data()!['city'] != null &&
            userDoc.data()!['country'] != null) {
          // Details exist, skip EnterDetailsPage
          Navigator.pushReplacementNamed(context, '/selectFavPerson');
        } else {
          // Details missing, go to EnterDetailsPage
          Navigator.pushReplacementNamed(context, '/enterDetails');
        }
      }
    } catch (e) {
      showCustomSnackBar(
        context,
        'Google sign-in failed: $e',
        icon: Icons.error_outline,
      );
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
              Image.asset('assets/logo.png', height: 80),
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
                style: TextStyle(fontSize: 14, color: Color(0xFF7B7B7B)),
              ),
              const SizedBox(height: 24),
              // Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Email
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: 'Email',
                        prefixIcon: const Icon(
                          Icons.email,
                          color: Color(0xFFEA8C6E),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
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
                        prefixIcon: const Icon(
                          Icons.lock,
                          color: Color(0xFFEA8C6E),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
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
                      ),
                      validator: (value) {
                        // Matches the backend's LoginRequest validation
                        // (app/schemas/auth.py: password just needs to be
                        // non-empty for a login attempt) — not the
                        // create-time password *policy*, which only
                        // applies to registration. See register_page.dart
                        // for that stricter check.
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Forgot Password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    if (_emailController.text.isEmpty) {
                      showCustomSnackBar(
                        context,
                        'Please enter your email first',
                        icon: Icons.info_outline,
                      );
                      return;
                    }
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(
                        email: _emailController.text.trim(),
                      );
                      showCustomSnackBar(
                        context,
                        'Password reset email sent!',
                        icon: Icons.check_circle_outline,
                      );
                    } on FirebaseAuthException catch (e) {
                      showCustomSnackBar(
                        context,
                        e.message ?? 'Error sending reset email',
                        icon: Icons.error_outline,
                      );
                    }
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(color: Color(0xFF7B7B7B)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Get Started Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA8C6E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
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
                      'Your information is private and protected. \n We\'re here for your peace of mind.',
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
                  const Expanded(
                    child: Divider(thickness: 1, color: Color(0xFFE0B8A4)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Or',
                      style: TextStyle(color: Color(0xFF7B7B7B)),
                    ),
                  ),
                  const Expanded(
                    child: Divider(thickness: 1, color: Color(0xFFE0B8A4)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Google Sign-In Button
              GestureDetector(
                onTap: () => signInWithGoogle(context),
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
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Color(0xFF7B7B7B)),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterPage(),
                        ),
                      );
                    },
                    child: const Text(
                      'Sign Up',
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
