import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

class SchedulerDetailsPage extends StatefulWidget {
  final List<Map<String, String>>? initialSchedule;
  final bool isViewMode;
  const SchedulerDetailsPage({Key? key, this.initialSchedule, this.isViewMode = false}) : super(key: key);

  @override
  State<SchedulerDetailsPage> createState() => _SchedulerDetailsPageState();
}

class _SchedulerDetailsPageState extends State<SchedulerDetailsPage> {
  List<Map<String, String>> schedule = [];

  @override
  void initState() {
    super.initState();
    schedule = widget.initialSchedule != null
        ? List<Map<String, String>>.from(widget.initialSchedule!)
        : List.generate(8, (_) => {'time': '', 'desc': ''});
  }

  void _addRow() {
    setState(() {
      schedule.add({'time': '', 'desc': ''});
    });
  }

  void _removeRow(int index) {
    setState(() {
      schedule.removeAt(index);
    });
  }

  void _save() async {
    // Save to Hive using today's date as key
    final box = Hive.box('schedulerBox');
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // Convert schedule (List<Map<String, String>>) to Map<String, String>
    Map<String, String> scheduleMap = {};
    for (final row in schedule) {
      final time = row['time'] ?? '';
      final desc = row['desc'] ?? '';
      if (time.isNotEmpty) {
        scheduleMap[time] = desc;
      }
    }
    await box.put(todayKey, scheduleMap);
    Navigator.pop(context, schedule);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAD1D1),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Scheduler', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 32)),
        centerTitle: false,
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 255, 247, 234),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Enter time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  SizedBox(width: 8),
                ],
              ),
              const Divider(thickness: 1, color: Color(0xFFFFD2B2)),
              Flexible(
                child: ListView.builder(
                  itemCount: schedule.length,
                  itemBuilder: (context, i) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            color: const Color(0xFFFFE0E0),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: widget.isViewMode ? null : () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay(
                                    hour: int.tryParse(schedule[i]['time']?.split('.')?.first ?? '6') ?? 6,
                                    minute: int.tryParse(schedule[i]['time']?.split('.')?.last ?? '0') ?? 0,
                                  ),
                                );
                                if (time != null) {
                                  setState(() {
                                    schedule[i]['time'] = '${time.hour.toString().padLeft(2, '0')}.${time.minute.toString().padLeft(2, '0')}';
                                  });
                                }
                              },
                              child: Container(
                                width: 80,
                                height: 48,
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFFBFAE),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      schedule[i]['time']?.isEmpty ?? true ? 'Click to enter' : schedule[i]['time']!,
                                      style: TextStyle(
                                        fontSize: (schedule[i]['time']?.isEmpty ?? true) ? 10 : 12,
                                        color: const Color(0xFF7A4F3C),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: TextField(
                              controller: TextEditingController(text: schedule[i]['desc']),
                              onChanged: widget.isViewMode ? null : (val) => schedule[i]['desc'] = val,
                              style: const TextStyle(fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'Enter here....',
                                border: InputBorder.none,
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFFFBFAE)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFFFBFAE)),
                                ),
                              ),
                              readOnly: widget.isViewMode,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Color(0xFFFFBFAE)),
                          onPressed: widget.isViewMode || schedule.length <= 1 ? null : () => _removeRow(i),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFFFFBFAE)),
                    onPressed: widget.isViewMode ? null : _addRow,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDA8D7A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            minimumSize: const Size(180, 48),
          ),
          onPressed: _save,
          child: const Text('Save', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
} 