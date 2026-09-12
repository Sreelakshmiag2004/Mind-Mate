import 'package:flutter/material.dart';

import 'core/network/api_exception.dart';
import 'custom_snackbar.dart';
import 'data/models/scheduler/scheduler_model.dart';
import 'data/repositories/scheduler_repository.dart';

class SchedulerDetailsPage extends StatefulWidget {
  final List<Map<String, String>>? initialSchedule;
  final bool isViewMode;
  const SchedulerDetailsPage({Key? key, this.initialSchedule, this.isViewMode = false}) : super(key: key);

  @override
  State<SchedulerDetailsPage> createState() => _SchedulerDetailsPageState();
}

class _SchedulerDetailsPageState extends State<SchedulerDetailsPage> {
  List<Map<String, String>> schedule = [];

  /// True while a save is in flight — disables the Save button and swaps
  /// its label for a spinner so a slow/duplicate tap can't fire a second
  /// overlapping PUT (PHASE11B).
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    schedule = widget.initialSchedule != null
        ? widget.initialSchedule!.map((row) => Map<String, String>.from(row)).toList()
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

  /// Saves the full day via `PUT /scheduler/{today}` (PHASE11B — replacing
  /// the old direct-to-Hive write). The UI is only updated, and the page
  /// only popped back to HomePage, once the backend confirms the save —
  /// never optimistically, and never on failure. On failure the user stays
  /// on this page with a clear, friendly error and nothing pretends to
  /// have succeeded.
  Future<void> _save() async {
    // PHASE11B: duplicate-time detection and the blank-time-row/blank-
    // description rules live in the pure, unit-tested `buildSchedulerRows`
    // (scheduler_model.dart) — this screen only decides what to show the
    // user when it refuses. `null` means two or more rows share a time;
    // nothing is sent to the backend in that case.
    final rows = buildSchedulerRows(schedule);
    if (rows == null) {
      showCustomSnackBar(
        context,
        'Two rows have the same time. Please use a different time for each row before saving.',
        icon: Icons.error_outline,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final saved = await SchedulerRepository.instance.replaceDay(DateTime.now(), rows);
      if (!mounted) return;
      final savedSchedule = saved.items
          .map((item) => {'time': colonTimeToDot(item.scheduledTime), 'desc': item.description ?? ''})
          .toList();
      setState(() {
        schedule = savedSchedule;
        _isSaving = false;
      });
      Navigator.pop(context, savedSchedule);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showCustomSnackBar(context, _friendlySchedulerError(e), icon: Icons.error_outline);
    }
  }

  /// Maps a Scheduler [ApiException] to a short, clean, user-facing
  /// message — same approach as `homepage.dart`'s `_friendlyChecklistError`/
  /// `_friendlyMoodError`. Every status this doesn't specifically name
  /// falls back to [ApiException.message], already documented as safe to
  /// show directly.
  String _friendlySchedulerError(ApiException e) {
    if (e is ValidationException) {
      return 'That schedule could not be saved — please check the times entered and try again.';
    }
    if (e is ConflictException) {
      return 'That schedule could not be saved because of a conflicting entry. Please try again.';
    }
    if (e is NetworkException) {
      return "Couldn't reach the server. Check your connection and try again.";
    }
    if (e is UnauthorizedException) {
      return 'Your session has expired. Please log in again.';
    }
    return 'Something went wrong saving your schedule. Please try again.';
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
                              onTap: widget.isViewMode || _isSaving ? null : () async {
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
                          onPressed: widget.isViewMode || _isSaving || schedule.length <= 1 ? null : () => _removeRow(i),
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
                    onPressed: widget.isViewMode || _isSaving ? null : _addRow,
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
          onPressed: (widget.isViewMode || _isSaving) ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Save', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
