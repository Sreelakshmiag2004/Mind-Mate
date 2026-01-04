import 'package:flutter/material.dart';
import 'custom_snackbar.dart';
import 'homepage.dart';

class MomPage extends StatefulWidget {
  const MomPage({super.key});

  @override
  State<MomPage> createState() => _MomPageState();
}

class _MomPageState extends State<MomPage> {
  void _onNextPressed() {
    showCustomSnackBar(
      context,
      'You selected: Mom',
      icon: Icons.check_circle_outline,
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFEBEE),
      body: SafeArea(
        child: Stack(
          children: [
            // Decorative leaves (use Positioned or a custom painter if you want to match the screenshot exactly)
            // For now, this is omitted for brevity
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1A1A1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: ClipOval(
                        child: Image.asset(
                          'assets/mom_child.png', // Make sure this asset exists and is listed in pubspec.yaml
                          width: 200,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      'Mom\'s love never truly fades💖',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 200,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _onNextPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDA8D7A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Next',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
