import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class JournalEntryPage extends StatefulWidget {
  final DateTime date;
  final int streak;
  final String? title;
  final String? description;
  final bool readOnly;

  const JournalEntryPage({
    super.key,
    required this.date,
    required this.streak,
    this.title,
    this.description,
    this.readOnly = false,
  });

  @override
  State<JournalEntryPage> createState() => _JournalEntryPageState();
}

class _JournalEntryPageState extends State<JournalEntryPage> {
  late TextEditingController titleController;
  late TextEditingController descController;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.title ?? '');
    descController = TextEditingController(text: widget.description ?? '');
  }

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String formattedDate = DateFormat('d MMMM yyyy').format(widget.date);
    return Scaffold(
      backgroundColor: const Color(0xFFFFEBEE),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    formattedDate,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    margin: const EdgeInsets.only(right: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.orange.shade200, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department, color: Colors.orange, size: 22),
                        const SizedBox(width: 4),
                        Text(widget.streak.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 60, left: 24, right: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Text('Title:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: titleController,
                          readOnly: widget.readOnly,
                          decoration: const InputDecoration(
                            hintText: 'Enter here....',
                            border: InputBorder.none,
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFDA8D7A), width: 1.2),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFDA8D7A), width: 2),
                            ),
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.asset(
                              'assets/scroll.png',
                              width: constraints.maxWidth ,
                              height: double.infinity,
                              fit: BoxFit.fill,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 30),
                                  const Center(
                                    child: Text(
                                      'Description',
                                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Expanded(
                                    child: TextField(
                                      controller: descController,
                                      maxLines: null,
                                      expands: true,
                                      readOnly: widget.readOnly,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter here....',
                                        border: InputBorder.none,
                                        hintStyle: TextStyle(color: Colors.grey, fontSize: 16),
                                        contentPadding: EdgeInsets.only(left: 22, top: 18, right: 20, bottom: 10),
                                      ),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: widget.readOnly
                        ? const SizedBox.shrink()
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDA8D7A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 16),
                            ),
                            onPressed: () {
                              Navigator.pop(context, {
                                'title': titleController.text,
                                'description': descController.text,
                              });
                            },
                            child: const Text('Done', style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
