import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'scheduler_details_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'favorite_page.dart';
import 'journal_page.dart';
import 'vault_password.dart';
import 'settings_page.dart';
import 'package:hive/hive.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Checklist state
  List<bool> checklist = [false, false, false, false, false];
  List<String> checklistItems = [
    'Drank enough water 💧',
    'Slept well last night 🛌',
    'Did one thing just for me 😉',
    'Got some fresh air and sunlight 🏝️',
    'Exercised well 🧘‍♂️',
  ];

  // Scheduler state
  List<String> times = ['9.00', '10.00', '11.00'];
  Map<String, String> schedule = {};

  // 1. Add state for selected month and year
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;

  // 2. Helper for month name
  String getMonthName(int month) {
    return DateFormat('MMMM').format(DateTime(0, month));
  }

  // 3. Mood chart mapping
  final List<Map<String, dynamic>> moodChart = [
    {'min': 0, 'max': 10, 'emoji': '😭'},
    {'min': 10, 'max': 20, 'emoji': '😳'},
    {'min': 20, 'max': 30, 'emoji': '😨'},
    {'min': 30, 'max': 40, 'emoji': '😟'},
    {'min': 40, 'max': 50, 'emoji': '😐'},
    {'min': 50, 'max': 60, 'emoji': '🙂'},
    {'min': 60, 'max': 70, 'emoji': '😊'},
    {'min': 70, 'max': 80, 'emoji': '😃'},
    {'min': 80, 'max': 90, 'emoji': '😄'},
    {'min': 90, 'max': 101, 'emoji': '🥳'},
  ];
  String getEmojiForPercent(int percent) {
    for (final entry in moodChart) {
      if (percent >= entry['min'] && percent < entry['max']) {
        return entry['emoji'];
      }
    }
    return '';
  }

  // 4. Mood data per day (key: yyyy-mm-dd)
  Map<String, int> moodPercentData = {};

  // Add state for calendar half view
  bool showFirstHalf = true;

  // Helper to get days in current half
  List<int> getVisibleDays(int year, int month, bool firstHalf) {
    int daysInMonth = DateUtils.getDaysInMonth(year, month);
    if (firstHalf) {
      return List.generate(15, (i) => i + 1);
    } else {
      return List.generate(daysInMonth - 15, (i) => i + 16);
    }
  }

  String getGreetingImage() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'assets/goodmorning.png';
    } else if (hour >= 12 && hour < 17) {
      return 'assets/goodafternoon.png';
    } else if (hour >= 17 && hour < 20) {
      return 'assets/goodevening.png';
    } else {
      return 'assets/goodnight.png';
    }
  }


  String? get userId {
    final user = FirebaseAuth.instance.currentUser;
    return user?.email?.split('@')[0];
  }

  // Helper for today's date string
  String get todayKey => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get yesterdayKey => DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

  // --- Firebase Load/Save Functions ---
  Future<void> loadChecklist() async {
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('checklist').doc(todayKey).get();
    if (doc.exists) {
      setState(() {
        checklist = List<bool>.from(doc['items']);
      });
    }
  }
  Future<void> saveChecklist() async {
    await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('checklist').doc(todayKey)
        .set({'items': checklist});
  }

  Future<void> loadScheduler() async {
    final box = Hive.box('schedulerBox');
    final todaySchedule = box.get(todayKey);
    if (todaySchedule != null) {
      setState(() {
        schedule = Map<String, String>.from(todaySchedule);
        times = schedule.keys.toList();
      });
    } else {
      // Try to load yesterday's scheduler if today is empty
      final yestSchedule = box.get(yesterdayKey);
      if (yestSchedule != null) {
        setState(() {
          schedule = Map<String, String>.from(yestSchedule);
          times = schedule.keys.toList();
        });
      } else {
        setState(() {
          schedule = {};
          times = [];
        });
      }
    }
  }
  Future<void> saveScheduler() async {
    final box = Hive.box('schedulerBox');
    await box.put(todayKey, schedule);
  }

  Future<void> loadMoods() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('moods').get();

    Map<String, int> allMoods = {};
    for (var doc in snapshot.docs) {
      final items = Map<String, int>.from(doc['items']);
      allMoods.addAll(items);
    }
    setState(() {
      moodPercentData = allMoods;
    });
  }
  Future<void> saveMoods() async {
    await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('moods').doc(todayKey)
        .set({'items': moodPercentData});
  }

  Future<void> saveMoodForDate(String dateKey, int percent) async {
    final docRef = FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('moods').doc(dateKey);

    final doc = await docRef.get();
    Map<String, int> items = {};
    if (doc.exists) {
      items = Map<String, int>.from(doc['items']);
    }
    items[dateKey] = percent;

    await docRef.set({'items': items});
  }

  Future<void> saveSchedulerForDate(String dateKey, Map<String, String> schedule) async {
    final box = Hive.box('schedulerBox');
    await box.put(dateKey, schedule);
  }

  // --- Reset at Midnight ---
  void _scheduleMidnightReset() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final duration = tomorrow.difference(now);
    Future.delayed(duration, () async {
      setState(() {
        checklist = List.filled(checklist.length, false);
      });
      _scheduleMidnightReset(); // Reschedule for the next day
    });
  }

  int _selectedIndex = 0;

  static const List<Map<String, dynamic>> _navItems = [
    {'icon': Icons.home, 'label': 'Home'},
    {'icon': Icons.menu_book, 'label': 'Journal'},
    {'icon': Icons.safety_check, 'label': 'Vault'},
    {'icon': Icons.favorite, 'label': 'Favorite'},
    {'icon': Icons.settings, 'label': 'Settings'},
  ];

  List<Widget> get _pages => [
    _buildHomeContent(),
    const JournalPage(),
    const VaultPasswordPage(),
    const FavouritesScreen(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    Firebase.initializeApp().then((_) async {
      await loadChecklist();
      await loadScheduler();
      await loadMoods();
      _scheduleMidnightReset();
    });
  }

  void _onNavBarTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Extract the current home content as a widget
  Widget _buildHomeContent() {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Good Morning Image Section
              Container(
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
                          getGreetingImage(),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 180,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Checklist Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 247, 234),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Checklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Color.fromARGB(255, 248, 200, 178),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset('assets/star.png', width: 20, height: 20),
                                  const SizedBox(width: 6),
                                  const Flexible(
                                    child: Text(
                                      "Turn your chaos into calm\nLet's tick things off together",
                                      style: TextStyle(fontSize: 11, color: Color.fromARGB(255, 0, 0, 0)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(checklistItems.length, (i) =>
                      Theme(
                        data: Theme.of(context).copyWith(
                          checkboxTheme: CheckboxThemeData(
                            shape: const CircleBorder(),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity(horizontal: -2, vertical: -2),
                          ),
                        ),
                        child: CheckboxListTile(
                          value: checklist[i],
                          onChanged: (val) {
                            setState(() {
                              checklist[i] = val ?? false;
                            });
                            saveChecklist();
                          },
                          title: Text(
                            checklistItems[i],
                            style: const TextStyle(fontSize: 15),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    Center(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFDA8D7A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          _showChecklistSummary();
                        },
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Scheduler Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 247, 234),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Scheduler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Color.fromARGB(255, 248, 200, 178),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset('assets/star.png', width: 20, height: 20),
                                  const SizedBox(width: 6),
                                  const Flexible(
                                    child: Text(
                                      "Plan peacefully,live mindfully!",
                                      style: TextStyle(fontSize: 11, color: Color.fromARGB(255, 0, 0, 0)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...sortedTimes.map((t) => Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Color.fromARGB(255, 255, 230, 230),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: Color.fromARGB(255, 248, 200, 178),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      t,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (schedule[t]?.isNotEmpty ?? false)
                                    ? schedule[t]![0].toUpperCase() + schedule[t]!.substring(1)
                                    : '',
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: isCurrentHour(t) ? 3 : 1,
                          decoration: BoxDecoration(
                            color: isCurrentHour(t) ? const Color(0xFFFFBFAE) : Color(0xFFFFBFAE),
                            boxShadow: isCurrentHour(t)
                                ? [
                                    BoxShadow(
                                      color: const Color.fromARGB(255, 250, 164, 164).withOpacity(0.7),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                      ],
                    )),
                    const SizedBox(height: 8),
                    Center(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFDA8D7A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SchedulerDetailsPage(
                                initialSchedule: sortedTimes.map((t) => {'time': t, 'desc': schedule[t] ?? ''}).toList(),
                              ),
                            ),
                          );
                          // Always reload from Hive after returning from the details page
                          await loadScheduler();
                        },
                        child: const Text('Edit'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Calendar Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 247, 234),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('Calendar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Color.fromARGB(255, 248, 200, 178),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset('assets/star.png', width: 20, height: 20),
                                  const SizedBox(width: 6),
                                  const Flexible(
                                    child: Text(
                                      "Feel it , track it ,understand it",
                                      style: TextStyle(fontSize: 11, color: Color.fromARGB(255, 0, 0, 0)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Add extra spacing before month/year selector row
                    const SizedBox(height: 12),
                    // Month and year selector row with calendar icon and arrows
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Single left arrow
                        IconButton(
                          icon: const Icon(Icons.arrow_left),
                          onPressed: () {
                            setState(() {
                              if (showFirstHalf) {
                                // Go to previous month, second half
                                if (selectedMonth == 1) {
                                  selectedMonth = 12;
                                  selectedYear--;
                                } else {
                                  selectedMonth--;
                                }
                                showFirstHalf = false;
                              } else {
                                // Go to first half of current month
                                showFirstHalf = true;
                              }
                            });
                          },
                        ),
                        Text(
                          '${getMonthName(selectedMonth)} $selectedYear',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        // Single right arrow
                        IconButton(
                          icon: const Icon(Icons.arrow_right),
                          onPressed: () {
                            setState(() {
                              if (!showFirstHalf && selectedMonth == 12) {
                                // Go to next year, first month, first half
                                selectedMonth = 1;
                                selectedYear++;
                                showFirstHalf = true;
                              } else if (!showFirstHalf) {
                                // Go to next month, first half
                                selectedMonth++;
                                showFirstHalf = true;
                              } else if (DateUtils.getDaysInMonth(selectedYear, selectedMonth) > 15) {
                                // Go to second half of current month
                                showFirstHalf = false;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      getMonthName(selectedMonth),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        childAspectRatio: 0.7,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: getVisibleDays(selectedYear, selectedMonth, showFirstHalf).length,
                      itemBuilder: (context, i) {
                        int day = getVisibleDays(selectedYear, selectedMonth, showFirstHalf)[i];
                        DateTime cellDate = DateTime(selectedYear, selectedMonth, day);
                        DateTime today = DateTime.now();
                        DateTime yesterday = today.subtract(const Duration(days: 1));
                        String key = '${selectedYear.toString().padLeft(4, '0')}-${selectedMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                        bool isToday = cellDate.year == today.year && cellDate.month == today.month && cellDate.day == today.day;
                        bool isYesterday = cellDate.year == yesterday.year && cellDate.month == yesterday.month && cellDate.day == yesterday.day;
                        int? percent = moodPercentData[key];
                        bool canEdit = isToday || isYesterday;
                        bool isPast = cellDate.isBefore(DateTime(today.year, today.month, today.day));
                        return GestureDetector(
                          onTap: canEdit ? () async {
                            int? entered = await showDialog<int>(
                              context: context,
                              builder: (context) {
                                int? tempPercent = percent;
                                return AlertDialog(
                                  title: Text('Enter mood % for $day ${getMonthName(selectedMonth)}'),
                                  content: TextField(
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Percent (0-100)'),
                                    onChanged: (val) {
                                      tempPercent = int.tryParse(val);
                                    },
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        if (tempPercent != null && tempPercent! >= 0 && tempPercent! <= 100) {
                                          Navigator.pop(context, tempPercent);
                                        } else {
                                          Navigator.pop(context);
                                        }
                                      },
                                      child: const Text('Save'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (entered != null) {
                              setState(() {
                                moodPercentData[key] = entered;
                              });
                              await saveMoodForDate(key, entered);
                              showDialog(
                                context: context,
                                barrierDismissible: true,
                                builder: (context) => Dialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    side: const BorderSide(color: Color(0xFFFFA07A), width: 1),
                                  ),
                                  backgroundColor: Colors.white,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Text(
                                          'Great!',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Montserrat',
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: 12),
                                        Text(
                                          "That's A Small Win&\nEvery Win Matters 💖",
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontFamily: 'Montserrat',
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                          } : null,
                          child: Container(
                            height: 80,
                            decoration: BoxDecoration(
                              color: Color.fromARGB(255, 255, 230, 230),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (isPast && percent == null)
                                  const Text(
                                    'Missed',
                                    style: TextStyle(fontSize: 10, color: Colors.red),
                                    textAlign: TextAlign.center,
                                  ),
                                if (percent != null)
                                  Text(
                                    getEmojiForPercent(percent),
                                    style: const TextStyle(fontSize: 24),
                                    textAlign: TextAlign.center,
                                  ),
                                if (canEdit && percent == null)
                                  const Text(
                                    'Click to enter',
                                    style: TextStyle(fontSize: 10),
                                    textAlign: TextAlign.center,
                                  ),
                                if (percent != null)
                                  Text(
                                    '$percent%',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                                    textAlign: TextAlign.center,
                                  ),
                                Text(
                                  day.toString(),
                                  style: const TextStyle(fontSize: 8, color: Color.fromARGB(255, 0, 0, 0)),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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

  void _showChecklistSummary() {
    int completed = checklist.where((v) => v).length;
    int total = checklist.length;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$completed/$total',
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '💗',
                    style: TextStyle(fontSize: 36),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Great work!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/star.png', width: 20, height: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Every tick is a win!',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addRow() {
    setState(() {
      // Generate a unique time string (e.g., next available hour)
      String newTime = _getNextAvailableTime();
      times.add(newTime);
      schedule[newTime] = '';
    });
  }

  void _removeRow(int index) {
    setState(() {
      String timeToRemove = times[index];
      times.removeAt(index);
      schedule.remove(timeToRemove);
    });
  }

  // Helper to generate a unique time string
  String _getNextAvailableTime() {
    int hour = 6;
    while (times.contains('${hour.toString().padLeft(2, '0')}.00')) {
      hour++;
      if (hour > 23) hour = 0;
    }
    return '${hour.toString().padLeft(2, '0')}.00';
  }

  // Before displaying scheduler entries, sort 'times' by time ascending
  List<String> get sortedTimes {
    List<String> sorted = List.from(times);
    sorted.sort((a, b) {
      double ta = double.tryParse(a.replaceAll(':', '.')) ?? 0;
      double tb = double.tryParse(b.replaceAll(':', '.')) ?? 0;
      return ta.compareTo(tb);
    });
    return sorted;
  }

  // Helper to check if a time string matches the current hour
  bool isCurrentHour(String t) {
    final now = TimeOfDay.now();
    final parts = t.split('.');
    if (parts.length < 1) return false;
    int hour = int.tryParse(parts[0]) ?? -1;
    return hour == now.hour;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 250, 209, 209),
      body: _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color.fromARGB(255, 208, 130, 112),
          unselectedItemColor: const Color.fromARGB(255, 99, 80, 80),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Montserrat'),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Montserrat'),
          currentIndex: _selectedIndex,
          onTap: _onNavBarTapped,
          items: _navItems.map((item) => BottomNavigationBarItem(
            icon: Icon(item['icon'], size: 25),
            label: item['label'],
          )).toList(),
        ),
      ),
    );
  }
} 