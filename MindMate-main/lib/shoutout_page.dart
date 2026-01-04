import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'custom_snackbar.dart';

class ShoutoutPage extends StatefulWidget {
  final String? title;
  final String? description;
  final String dateKey;
  final String? userId;

  const ShoutoutPage({
    Key? key,
    this.title,
    this.description,
    required this.dateKey,
    required this.userId,
  }) : super(key: key);

  @override
  State<ShoutoutPage> createState() => _ShoutoutPageState();
}

class _ShoutoutPageState extends State<ShoutoutPage> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title ?? '');
    _descController = TextEditingController(text: widget.description ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _saveShoutout() async {
    if (widget.userId == null || _titleController.text.trim().isEmpty || _descController.text.trim().isEmpty) {
      showCustomSnackBar(context, 'Please fill in all fields.');
      return;
    }
    setState(() { _loading = true; });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('shoutouts')
          .doc(widget.dateKey)
          .set({
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      showCustomSnackBar(context, 'Shoutout saved!');
      Navigator.of(context).pop(true);
    } catch (e) {
      showCustomSnackBar(context, 'Failed to save shoutout.');
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBE3E3),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Shoutout', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Give Us A Title',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: 'Enter here....',
                        filled: true,
                        fillColor: const Color(0xFFF9D7C7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'What Is It?',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descController,
                      minLines: 5,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: 'Enter here....',
                        filled: true,
                        fillColor: const Color(0xFFF9D7C7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    Center(
                      child: SizedBox(
                        width: 200,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE89C6D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _loading ? null : _saveShoutout,
                          child: _loading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Done', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 