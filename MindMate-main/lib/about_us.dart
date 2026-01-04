import 'package:flutter/material.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD9D0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E9),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFDD5D1), Color(0xFFE7BBAA)],
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 16, left: 8, right: 8, bottom: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'About us',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top banner image styled like homepage.dart (now scrolls)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                          child: Container(
                            width: double.infinity,
                            height: 180,
                            decoration: BoxDecoration(
                              color: Colors.pink[100],
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                'assets/stress.png',
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 180,
                              ),
                            ),
                          ),
                        ),
                        // Add stress image at the top of the scrollable content
                      
                        const SizedBox(height: 18),
                        const SizedBox(height: 12),
                        // Welcome text
                        const Text(
                          'Welcome to MindMate – your personal companion in the journey toward peace, balance, and emotional well-being.',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(height: 18),
                        // First row: image right, text left
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: const Text(
                                "In today's fast-paced world, stress becomes a constant companion. MindMate was created to offer a peaceful space where your mind feels heard, calm, and supported.",
                                style: TextStyle(fontSize: 15),
                                textAlign: TextAlign.left,
                              ),
                            ),
                            const SizedBox(width: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                              child: Image.asset(
                                'assets/head.png',
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // Second row: image left, text right
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                              child: Image.asset(
                                'assets/bulb.png',
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: const Text(
                                "We believe mental relaxation should be simple and soothing. From calming sounds to gentle reminders, MindMate helps you find peace in small moments.",
                                style: TextStyle(fontSize: 15),
                                textAlign: TextAlign.left,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // Third row: image right, text left
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: const Text(
                                "We believe mental relaxation should be simple and soothing. From calming sounds to gentle reminders, MindMate helps you find peace in small moments.",
                                style: TextStyle(fontSize: 15),
                                textAlign: TextAlign.left,
                              ),
                            ),
                            const SizedBox(width: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                              child: Image.asset(
                                'assets/life.png',
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // Fourth row: image left, text right
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                              child: Image.asset(
                                'assets/cup.png',
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: const Text(
                                "MindMate is designed with care, calm visuals, and easy guidance to help you reconnect, relax, and clear your mind with every click.",
                                style: TextStyle(fontSize: 15),
                                textAlign: TextAlign.left,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // Last text block
                        const Text(
                          "We're more than just an app – we're a friend that listens without judgment and stays by your side, one mindful moment at a time.",
                          style: TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 24),
                        // Optionally, add a heart or logo at the bottom
                        // Center(
                        //   child: Icon(Icons.favorite, color: Colors.pinkAccent, size: 36),
                        // ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 