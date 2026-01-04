import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'journal_entry_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'custom_snackbar.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({Key? key}) : super(key: key);

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  DateTime selectedDate = DateTime.now();
  final TextEditingController problemController = TextEditingController();
  String shoutout = '';
  String problem = '';
  String selectedIssue = 'Not Listening, Just Blaming';
  bool? feelBetter;
  bool showCongrats = false;
  bool hasEntry = false;
  String entryTitle = '';
  String entryDescription = '';
  int streak = 0;
  String? todayShoutoutTitle;
  String? todayShoutoutDescription;
  String? yesterdayShoutoutTitle;
  bool? yesterdayFeelBetter;
  bool showFeelBetterCongrats = false;
  bool showFeelBetterComfort = false;

  String? get userId {
    final user = FirebaseAuth.instance.currentUser;
    return user?.email?.split('@')[0];
  }

  @override
  void initState() {
    super.initState();
    _loadTodayJournal();
    _loadTodayShoutout();
    _loadYesterdayShoutout();
    _scheduleMidnightReset();
  }

  Future<void> _loadTodayJournal() async {
    if (userId == null) return;
    final todayKey = _dateKey(DateTime.now());
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('journals').doc(todayKey).get();
    if (doc.exists) {
      setState(() {
        hasEntry = true;
        entryTitle = doc['title'] ?? '';
        entryDescription = doc['description'] ?? '';
        streak = doc['streak'] ?? 0;
        showCongrats = true;
      });
    } else {
      setState(() {
        hasEntry = false;
        entryTitle = '';
        entryDescription = '';
        showCongrats = false;
      });
    }
  }

  Future<void> _saveJournal(String title, String description, DateTime date) async {
    if (userId == null) return;
    final dateKey = _dateKey(date);
    int newStreak = await _calculateStreak(dateKey);
    await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('journals').doc(dateKey)
        .set({
      'title': title,
      'description': description,
      'date': dateKey,
      'streak': newStreak,
    });
    setState(() {
      hasEntry = true;
      entryTitle = title;
      entryDescription = description;
      streak = newStreak;
      showCongrats = true;
    });
  }

  Future<void> _loadJournalForDate(DateTime date) async {
    if (userId == null) return;
    final dateKey = _dateKey(date);
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('journals').doc(dateKey).get();
    if (doc.exists) {
      setState(() {
        hasEntry = true;
        entryTitle = doc['title'] ?? '';
        entryDescription = doc['description'] ?? '';
        streak = doc['streak'] ?? 0;
        showCongrats = true;
      });
    } else {
      setState(() {
        hasEntry = false;
        entryTitle = '';
        entryDescription = '';
        showCongrats = false;
        streak = 0;
      });
    }
  }

  Future<int> _calculateStreak(String todayKey) async {
    if (userId == null) return 1;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey = _dateKey(yesterday);
    final yesterdayDoc = await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('journals').doc(yesterdayKey).get();
    if (yesterdayDoc.exists) {
      int prevStreak = yesterdayDoc['streak'] ?? 0;
      // Check if yesterday's entry was consecutive
      return prevStreak + 1;
    } else {
      // Missed a day, reset streak
      return 1;
    }
  }

  Future<void> _loadTodayShoutout() async {
    if (userId == null) return;
    final todayKey = _dateKey(DateTime.now());
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('shoutouts').doc(todayKey).get();
    if (doc.exists) {
      setState(() {
        todayShoutoutTitle = doc['title'] ?? '';
        todayShoutoutDescription = doc['description'] ?? '';
      });
    } else {
      setState(() {
        todayShoutoutTitle = null;
        todayShoutoutDescription = null;
      });
    }
  }

  Future<void> _loadYesterdayShoutout() async {
    if (userId == null) return;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey = _dateKey(yesterday);
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('shoutouts').doc(yesterdayKey).get();
    if (doc.exists) {
      setState(() {
        yesterdayShoutoutTitle = doc['title'] ?? '';
        yesterdayFeelBetter = doc['feelBetter'];
      });
    } else {
      setState(() {
        yesterdayShoutoutTitle = null;
        yesterdayFeelBetter = null;
      });
    }
  }

  void _resetShoutoutLocal() {
    setState(() {
      todayShoutoutTitle = null;
      todayShoutoutDescription = null;
      yesterdayShoutoutTitle = null;
    });
  }

  void _scheduleMidnightReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final duration = tomorrow.difference(now);
    Future.delayed(duration, () async {
      setState(() {
        hasEntry = false;
        entryTitle = '';
        entryDescription = '';
        showCongrats = false;
        // Do not reset streak here, as it is managed by Firestore
        showFeelBetterCongrats = false;
        showFeelBetterComfort = false;
        yesterdayFeelBetter = null;
      });
      _resetShoutoutLocal();
      _scheduleMidnightReset(); 
      _loadTodayJournal(); 
      _loadTodayShoutout(); 
    });
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    problemController.dispose();
    super.dispose();
  }

  Future<void> _saveShoutout() async {
    if (userId == null || problemController.text.trim().isEmpty) {
      showCustomSnackBar(context, 'Please enter a problem.');
      return;
    }
    try {
      final problemText = problemController.text.trim();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('shoutouts')
          .add({
        'problem': problemText,
        'timestamp': FieldValue.serverTimestamp(),
      });
      showCustomSnackBar(context, 'Shoutout added!');
      problemController.clear();
      setState(() {
        selectedIssue = problemText;
      });
    } catch (e) {
      showCustomSnackBar(context, 'Failed to add shoutout.');
    }
  }

  Future<void> _setYesterdayFeelBetter(bool value) async {
    setState(() {
      yesterdayFeelBetter = value;
      if (value == true) {
        showFeelBetterCongrats = true;
      } else {
        showFeelBetterComfort = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 251, 213, 213),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0),
                child: Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.pink[100],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/journal_bg.png',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 180,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 45,
                        child: Center(
                          child: Text(
                            'Journal Space',
                            style: const TextStyle(
                              fontFamily: 'Puppies Play',
                              fontSize: 70,
                              color: Color(0xFF7B3F1D),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Journal Section
                    Row(
                      children: [
                        const Text(
                          'Journal',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Color.fromARGB(255, 248, 200, 178),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.star, color: Color(0xFFFFB300), size: 22),
                              SizedBox(width: 6),
                              Text(
                                'Write your heart out, this space\nhears without judgement',
                                style: TextStyle(fontSize: 12, color: Color(0xFF5A3A1B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Date',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFDA8D7A),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      readOnly: true,
                                      controller: TextEditingController(
                                        text: DateFormat('MM/dd/yyyy').format(selectedDate),
                                      ),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(color: Color(0xFFDA8D7A), width: 1),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(color: Color(0xFFDA8D7A), width: 2),
                                        ),
                                        suffixIcon: IconButton(
                                          icon: const Icon(Icons.calendar_today, size: 18, color: Color(0xFFDA8D7A)),
                                          onPressed: () async {
                                            DateTime? picked = await showDatePicker(
                                              context: context,
                                              initialDate: selectedDate,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100),
                                            );
                                            if (picked != null) {
                                              setState(() {
                                                selectedDate = picked;
                                              });
                                              _loadJournalForDate(selectedDate);
                                            }
                                          },
                                        ),
                                      ),
                                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFDA8D7A),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                                      elevation: 0,
                                    ),
                                    onPressed: () async {
                                      await _loadJournalForDate(selectedDate);
                                      if (hasEntry) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => JournalEntryPage(
                                              date: selectedDate,
                                              streak: streak,
                                              title: entryTitle,
                                              description: entryDescription,
                                              readOnly: true,
                                            ),
                                          ),
                                        );
                                      } else {
                                        showCustomSnackBar(context, 'No journal entry for this date.');
                                      }
                                    },
                                    child: const Text('View', style: TextStyle(fontSize: 15, color: Colors.white)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'MM/DD/YYYY',
                                style: TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w400),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Scroll streak
                          LayoutBuilder(
                            builder: (context, constraints) {
                              double scrollWidth = constraints.maxWidth - 26; // 18px padding on each side
                              double scrollHeight = 1.5 * scrollWidth; // Adjust as needed for your image ratio

                              return Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Enlarged Scroll background
                                    Image.asset(
                                      'assets/scroll.png',
                                      width: scrollWidth,
                                      height: scrollHeight,
                                      fit: BoxFit.fill,
                                    ),
                                    // Content on top of scroll
                                    SizedBox(
                                      width: scrollWidth * 0.8, // Keep content within scroll area
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (showCongrats)
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(color: Colors.orange.shade200, width: 1),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                                                      SizedBox(width: 4),
                                                      Text(streak.toString(), style: TextStyle(fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 18),
                                                const Text(
                                                  'Great!\nEvery Feeling\nDeserves A Page',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                                ),
                                              ],
                                            )
                                          else
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Fire streak
                                                Container(
                                                  margin: const EdgeInsets.only(bottom: 18),
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(500),
                                                    border: Border.all(color: Colors.orange.shade200, width: 1),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                                                      SizedBox(width: 6),
                                                      Text(streak.toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 18),
                                                const Text(
                                                  'Pending...\nLet\'s complete',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                                ),
                                              ],
                                            ),
                                          const SizedBox(height: 22),
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                                                colors: [
                                                  Color(0xFFA86F1F), // 0%
                                                  Color(0xFFC98C2B), // 25%
                                                  Color(0xFFEFC162), // 50%
                                                  Color(0xFFD9943C), // 75%
                                                  Color(0xFF9B611C), // 100%
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(32),
                                            ),
                                            height: 30,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(32),
                                                ),
                                                padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 0),
                                              ),
                                              onPressed: DateTime.now().year == selectedDate.year && DateTime.now().month == selectedDate.month && DateTime.now().day == selectedDate.day
                                                  ? () async {
                                                      await _loadJournalForDate(selectedDate);
                                                      if (hasEntry) {
                                                        // Edit mode
                                                        final result = await Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) => JournalEntryPage(
                                                              date: selectedDate,
                                                              streak: streak,
                                                              title: entryTitle,
                                                              description: entryDescription,
                                                              readOnly: false,
                                                            ),
                                                          ),
                                                        );
                                                        if (result is Map) {
                                                          setState(() {
                                                            hasEntry = true;
                                                            entryTitle = result['title'] ?? '';
                                                            entryDescription = result['description'] ?? '';
                                                            showCongrats = true;
                                                          });
                                                          _saveJournal(entryTitle, entryDescription, selectedDate);
                                                        }
                                                      } else {
                                                        // Write mode
                                                        final result = await Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) => JournalEntryPage(
                                                              date: selectedDate,
                                                              streak: streak,
                                                            ),
                                                          ),
                                                        );
                                                        if (result is Map) {
                                                          setState(() {
                                                            hasEntry = true;
                                                            entryTitle = result['title'] ?? '';
                                                            entryDescription = result['description'] ?? '';
                                                            showCongrats = true;
                                                          });
                                                          _saveJournal(entryTitle, entryDescription, selectedDate);
                                                        }
                                                      }
                                                    }
                                                  : () {
                                                      showCustomSnackBar(context, "You can only write or  today's journal.");
                                                    },
                                              child: Text(hasEntry ? 'Edit' : "Let's Write", style: const TextStyle(fontSize: 16, color: Colors.black)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Shoutout Section
                    Row(
                      children: [
                        const Text(
                          'Shoutout',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7C7B0),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.star, color: Color(0xFFFFB300), size: 22),
                              SizedBox(width: 6),
                              Text(
                                'A safe space to unburden your\nheart.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF5A3A1B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Add a view-only textbox at the top, only if no shoutout for today
                          if (todayShoutoutTitle == null || todayShoutoutTitle!.isEmpty)
                            TextField(
                              readOnly: true,
                              decoration: InputDecoration(
                                hintText: 'What\'s Weighing on your mind? ',
                                filled: true,
                                fillColor: const Color(0xFFF9D7C7),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                              style: const TextStyle(fontSize: 16, color: Colors.black54),
                            ),
                          if (todayShoutoutTitle == null || todayShoutoutTitle!.isEmpty)
                            const SizedBox(height: 16),
                          if (todayShoutoutTitle != null && todayShoutoutTitle!.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Today\'s Shoutout:', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text(todayShoutoutTitle ?? '', style: const TextStyle(fontSize: 16)),
                                if (todayShoutoutDescription != null && todayShoutoutDescription!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(todayShoutoutDescription ?? '', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                                  ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          Center(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDA8D7A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(80),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 0),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                // Navigate to shoutout page for add/edit
                                final result = await Navigator.pushNamed(context, '/shoutout', arguments: {
                                  'title': todayShoutoutTitle,
                                  'description': todayShoutoutDescription,
                                  'dateKey': _dateKey(DateTime.now()),
                                  'userId': userId,
                                });
                                if (result == true) {
                                  _loadTodayShoutout();
                                  _loadYesterdayShoutout();
                                }
                              },
                              child: Text(
                                (todayShoutoutTitle != null && todayShoutoutTitle!.isNotEmpty) ? 'Edit' : 'Add',
                                style: const TextStyle(fontSize: 18, color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (yesterdayShoutoutTitle != null && yesterdayShoutoutTitle!.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Color(0xFFDA8D7A)),
                              ),
                              child: showFeelBetterCongrats
                                  ? SizedBox(
                                      height: 180,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            'Great!',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            "That's A Small Win&\nEvery Win Matters ",
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.black,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            '💗',
                                            style: TextStyle(fontSize: 28),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  : showFeelBetterComfort
                                    ? SizedBox(
                                        height: 180,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text(
                                              "It's Ok To Not Be Okay! It Will Be Fine Soon",
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 16),
                                            const Text(
                                              '💗',
                                              style: TextStyle(fontSize: 28),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          const Text(
                                            'Do You Feel Better Now About',
                                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            yesterdayShoutoutTitle ?? '',
                                            style: const TextStyle(
                                              fontSize: 22,
                                              color: Color(0xFFDA8D7A),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 18),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 90,
                                                height: 40,
                                                child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Color(0xFFDA8D7A),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(32),
                                                    ),
                                                    elevation: 0,
                                                  ),
                                                  onPressed: () => _setYesterdayFeelBetter(true),
                                                  child: const Text(
                                                    'Yes',
                                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                width: 90,
                                                height: 40,
                                                child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Color(0xFFDA8D7A),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(32),
                                                    ),
                                                    elevation: 0,
                                                  ),
                                                  onPressed: () => _setYesterdayFeelBetter(false),
                                                  child: const Text(
                                                    'No',
                                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                            ),
                          if (yesterdayShoutoutTitle == null || yesterdayShoutoutTitle!.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Color(0xFFDA8D7A)),
                              ),
                              child: const Center(
                                child: Text(
                                  'No shoutout recorded yesterday.',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFDA8D7A)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 