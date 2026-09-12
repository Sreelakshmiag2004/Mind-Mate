import 'package:flutter/material.dart';

import 'core/network/api_exception.dart';
import 'custom_snackbar.dart';
import 'data/models/journal/journal_model.dart' show parseDateOnly;
import 'data/repositories/shoutout_repository.dart';

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

  /// Saves this day's Shoutout via `ShoutoutRepository.createOrUpdate`
  /// (PHASE13 — replacing the old direct Firestore `.set()`, which always
  /// silently overwrote any existing entry for [widget.dateKey]). Title
  /// and description must still both be non-empty — PHASE13 Step 4 keeps
  /// this screen's existing validation as-is even though the backend
  /// itself allows both fields to be null. [widget.userId] is no longer
  /// read here: the backend derives the acting user from the Bearer
  /// token, never from a client-supplied id (PHASE13: "never send
  /// user_id").
  ///
  /// The UI is only updated, and this screen only popped back to
  /// JournalPage, once the backend confirms the save — never
  /// optimistically. On failure, the user stays on this page with a
  /// clear, friendly error and nothing pretends to have succeeded.
  Future<void> _saveShoutout() async {
    if (_titleController.text.trim().isEmpty || _descController.text.trim().isEmpty) {
      showCustomSnackBar(context, 'Please fill in all fields.');
      return;
    }
    setState(() { _loading = true; });
    try {
      await ShoutoutRepository.instance.createOrUpdate(
        entryDate: parseDateOnly(widget.dateKey),
        title: _titleController.text.trim(),
        content: _descController.text.trim(),
      );
      if (!mounted) return;
      showCustomSnackBar(context, 'Shoutout saved!');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyShoutoutError(e), icon: Icons.error_outline);
    } finally {
      if (mounted) {
        setState(() { _loading = false; });
      }
    }
  }

  /// Maps a Shoutout [ApiException] to a short, clean, user-facing
  /// message — same approach as `journal_page.dart`'s
  /// `_friendlyJournalError`. Every status this doesn't specifically name
  /// falls back to [ApiException.message], already documented as safe to
  /// show directly.
  String _friendlyShoutoutError(ApiException e) {
    if (e is ConflictException) {
      return "That date's shoutout couldn't be saved — please try again.";
    }
    if (e is ValidationException) {
      return "That shoutout couldn't be saved — please shorten the title or text and try again.";
    }
    if (e is NetworkException) {
      return "Couldn't reach the server. Check your connection and try again.";
    }
    if (e is UnauthorizedException) {
      return 'Your session has expired. Please log in again.';
    }
    return 'Something went wrong saving your shoutout. Please try again.';
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