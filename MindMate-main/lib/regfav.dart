import 'package:flutter/material.dart';
import 'custom_snackbar.dart';
import 'mom_page.dart';
import 'dad_page.dart';
import 'sibling_page.dart';
import 'bestfriend_page.dart';
import 'lovers_page.dart';
import 'grand_page.dart';
import 'others_page.dart';
import 'homepage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class RegFavPage extends StatefulWidget {
  const RegFavPage({super.key});

  @override
  State<RegFavPage> createState() => _RegFavPageState();
}

class _RegFavPageState extends State<RegFavPage> {
  String? _selectedPerson;
  final TextEditingController _otherController = TextEditingController();
  final TextEditingController _otherRelationController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  final List<Map<String, String>> _options = [
    {'label': 'Mom', 'image': 'assets/mom1.png'},
    {'label': 'Dad', 'image': 'assets/dad1.png'},
    {'label': 'Siblings', 'image': 'assets/sibling1.png'},
    {'label': 'Best Friend', 'image': 'assets/bestfriend1.png'},
    {'label': 'Love', 'image': 'assets/lovers1.png'},
    {'label': 'Grandparents', 'image': 'assets/grandparents1.png'},
    {'label': 'Others', 'image': ''},
  ];

  @override
  void dispose() {
    _otherController.dispose();
    _otherRelationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _isDoneEnabled {
    if (_selectedPerson == null) return false;
    if (_selectedPerson == 'Others') {
      return _otherController.text.trim().isNotEmpty && _otherRelationController.text.trim().isNotEmpty;
    } else {
      return _noteController.text.trim().isNotEmpty;
    }
  }

  void _saveComfortPerson() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showCustomSnackBar(context, 'You are not logged in!');
      return;
    }

    final username = user.email!.split('@')[0];
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(username);

    String relation = _selectedPerson ?? '';
    String name = _noteController.text.trim();
    String customRelation = _otherRelationController.text.trim();

    Map<String, dynamic> comfortPersonData = {};

    if (relation == 'Others') {
      name = _otherController.text.trim();
      comfortPersonData = {
        'relation': 'Others',
        'name': name,
        'customRelation': customRelation,
      };
    } else {
      comfortPersonData = {
        'relation': relation,
        'name': name,
        'customRelation': null,
      };
    }

    try {
      await userDocRef.update({'comfortPerson': comfortPersonData});
      final encodedName = Uri.encodeComponent(name);
      final encodedRelation = Uri.encodeComponent(relation);
      final inviteLink = 'mindmate://invite?from=${user?.uid}&name=$encodedName&relation=$encodedRelation';

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invite Link Created!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(inviteLink),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inviteLink));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied!')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share',
                    onPressed: () {
                      Share.share(inviteLink);
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                  (route) => false,
                );
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      showCustomSnackBar(
        context,
        'Failed to save. Please try again.',
        icon: Icons.error_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDD5D1), // Light pink
      body: SafeArea(
        child: Column(
          children: [
            // Header with gradient (full width, no side padding)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFD18573), Color(0xFFFBDACC)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.only(top: 24, bottom: 18),
              child: const Center(
                child: Text(
                  'Select Your Comfort Person',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            // Rest of the content with horizontal padding
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF8E1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC107), size: 28),
                                        SizedBox(width: 8),
                                        Text(
                                          'Info',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      "By selecting your favourite person, a special link will be generated — one you can share with someone you trust. Once they join, they can gently monitor your stress levels. In moments when you're feeling overwhelmed, they'll be able to reach out, call you, and be your comfort — just when you need it the most. Because knowing someone's looking out for you can bring the calm you deserve.",
                                      style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.35),
                                      textAlign: TextAlign.justify,
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC107), size: 28),
                            SizedBox(width: 8),
                            Text(
                              'Important Note',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Options
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._options.map(
                              (option) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Radio<String>(
                                      value: option['label']!,
                                      groupValue: _selectedPerson,
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedPerson = value;
                                          _noteController.clear();
                                          _otherController.clear();
                                          _otherRelationController.clear();
                                        });
                                      },
                                      activeColor: const Color(0xFFDA8D7A),
                                    ),
                                    Text(
                                      option['label']!,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(width: 9),
                                    if (option['label'] != 'Others' && option['image']!.isNotEmpty)
                                      Image.asset(
                                        option['image']!,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.contain,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_selectedPerson == 'Others')
                              Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: TextField(
                                      controller: _otherController,
                                      style: const TextStyle(fontSize: 14),
                                      decoration: const InputDecoration(
                                        filled: true,
                                        fillColor: Color(0xFFF9E7E3),
                                        hintText: 'Enter Name',
                                        hintStyle: TextStyle(fontSize: 13, color: Colors.black38, fontWeight: FontWeight.w400),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(
                                            color: Color(0xFFDA8D7A),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: TextField(
                                      controller: _otherRelationController,
                                      style: const TextStyle(fontSize: 14),
                                      decoration: const InputDecoration(
                                        filled: true,
                                        fillColor: Color(0xFFF9E7E3),
                                        hintText: 'Enter Relationship',
                                        hintStyle: TextStyle(fontSize: 13, color: Colors.black38, fontWeight: FontWeight.w400),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(
                                            color: Color(0xFFDA8D7A),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                            if (_selectedPerson != null && _selectedPerson != 'Others')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: TextField(
                                  controller: _noteController,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: Color(0xFFF9E7E3),
                                    hintText: 'Enter Name',
                                    hintStyle: TextStyle(fontSize: 13, color: Colors.black38, fontWeight: FontWeight.w400),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(8)),
                                      borderSide: BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(8)),
                                      borderSide: BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(8)),
                                      borderSide: BorderSide(
                                        color: Color(0xFFDA8D7A),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            const SizedBox(height: 18),
                            Center(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD18573),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 57,
                                    vertical: 13,
                                  ),
                                ),
                                onPressed: _isDoneEnabled ? _saveComfortPerson : null,
                                child: const Text(
                                  'Done',
                                  style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (context) => const HomePage()),
                                    (route) => false,
                                  );
                                },
                                child: const Text(
                                  'Skip',
                                  style: TextStyle(fontSize: 14, color: Color(0xFFDA8D7A)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Color(0xFF7B7B7B),
                          ),
                          const SizedBox(width: 3),
                          const Flexible(
                            child: Text(
                              'Your information is private and protected. We\'re here for your peace of mind.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7B7B7B),
                              ),
                              textAlign: TextAlign.center,
                            ),
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
    );
  }
}
