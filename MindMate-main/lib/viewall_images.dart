import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'image_note.dart';
import 'dart:io';
import 'vault.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

class ViewAllImagesPage extends StatefulWidget {
  const ViewAllImagesPage({Key? key}) : super(key: key);

  @override
  State<ViewAllImagesPage> createState() => _ViewAllImagesPageState();
}

class _ViewAllImagesPageState extends State<ViewAllImagesPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD9D0),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                  SizedBox(width: 8),
                  Text('Images', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SearchBar(
                onAdd: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    allowMultiple: false,
                  );
                  if (result != null && result.files.single.path != null) {
                    final file = File(result.files.single.path!);
                    final id = const Uuid().v4();
                    final note = ImageNote(
                      id: id,
                      path: file.path,
                      title: capitalizeIfNeeded(result.files.single.name),
                      date: DateTime.now(),
                    );
                    await Hive.box<ImageNote>('image_notes').add(note);
                  }
                },
                isRecording: false,
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: _VaultSectionCard(
                  child: ValueListenableBuilder(
                    valueListenable: Hive.box<ImageNote>('image_notes').listenable(),
                    builder: (context, Box<ImageNote> box, _) {
                      final notes = (box.values.toList()..sort((a, b) => b.date.compareTo(a.date)))
                          .where((n) => n.title.toLowerCase().contains(_search.toLowerCase())).toList();
                      if (notes.isEmpty) {
                        return const Center(child: Text('No images uploaded'));
                      }
                      return ListView.separated(
                        itemCount: notes.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8),
                        itemBuilder: (context, i) => _ImageListItem(
                          note: notes[i],
                          onMenu: () => _showImageMenu(context, notes[i]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultSectionCard extends StatelessWidget {
  final Widget child;
  const _VaultSectionCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

class _ImageListItem extends StatelessWidget {
  final ImageNote note;
  final VoidCallback onMenu;
  const _ImageListItem({required this.note, required this.onMenu});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Color(0xFFFDDED0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(note.path),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(note.path),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title.length > 10 ? note.title.substring(0, 10) + '...' : note.title,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(DateFormat('dd-MM-yy').format(note.date), style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.more_vert, color: Colors.grey),
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

void _showImageMenu(BuildContext context, ImageNote note) {
  showModalBottomSheet(
    context: context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(Icons.edit),
          title: Text('Rename'),
          onTap: () async {
            Navigator.pop(context);
            final newTitle = await _showRenameDialog(context, note.title);
            if (newTitle != null && newTitle.isNotEmpty) {
              note.title = capitalizeIfNeeded(newTitle);
              await note.save();
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.delete),
          title: Text('Delete'),
          onTap: () async {
            Navigator.pop(context);
            await note.delete();
          },
        ),
      ],
    ),
  );
}

Future<String?> _showRenameDialog(BuildContext context, String currentTitle) async {
  final controller = TextEditingController(text: currentTitle);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Rename Image'),
      content: TextField(controller: controller),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text('Rename')),
      ],
    ),
  );
}

String capitalizeIfNeeded(String input) {
  if (input.isEmpty) return input;
  if (double.tryParse(input[0]) != null) return input;
  return input[0].toUpperCase() + input.substring(1);
}

class _SearchBar extends StatelessWidget {
  final VoidCallback? onAdd;
  final bool isRecording;
  final ValueChanged<String>? onChanged;
  const _SearchBar({this.onAdd, this.isRecording = false, this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search',
          prefixIcon: Icon(Icons.search, color: Colors.grey, size: 18),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: onAdd != null
              ? IconButton(
                  icon: Icon(isRecording ? Icons.stop : Icons.add, color: Color.fromARGB(255, 234, 152, 115), size: 22),
                  onPressed: onAdd,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minHeight: 32, minWidth: 32),
                )
              : null,
        ),
        style: TextStyle(fontSize: 13),
        onChanged: onChanged,
      ),
    );
  }
} 