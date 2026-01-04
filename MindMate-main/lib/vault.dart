import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'homepage.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'image_note.dart';
import 'viewall_images.dart';
import 'video_note.dart';
import 'viewall_videos.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
part 'vault.g.dart';

class VaultPage extends StatefulWidget {
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  Future<String> getLastViewed() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return 'Never';
    final username = user!.email!.split('@')[0];
    final doc = await FirebaseFirestore.instance.collection('users').doc(username).get();
    final ts = doc.data()?['vaultLastViewed'];
    if (ts == null) return 'Never';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    } else {
      return 'Never';
    }
    return DateFormat('dd MMMM, yyyy | HH:mm').format(dt);
  }

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentPlayingId;
  bool _isFloatingRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _timer;
  String? _currentRecordingPath;
  String _voiceNoteSearch = '';
  String _imageSearch = '';
  String _videoSearch = '';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      print('No microphone permission!');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/${const Uuid().v4()}.m4a';
    await _recorder.start(const RecordConfig(), path: filePath);
    setState(() { _isRecording = true; });
  }

  Future<void> _stopRecordingAndSave() async {
    final path = await _recorder.stop();
    setState(() { _isRecording = false; });
    if (path == null) return;
    final file = File(path);
    final duration = await _audioPlayer.setSourceDeviceFile(path).then((_) => _audioPlayer.getDuration());
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;
    final username = user!.email!.split('@')[0];
    final id = const Uuid().v4();
    final title = 'Voice Note';
    // Upload to Firebase Storage
    final ref = FirebaseStorage.instance.ref().child('voice_notes/$username/$id.m4a');
    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    final note = VoiceNote(
      id: id,
      title: title,
      url: url,
      localPath: path,
      date: DateTime.now(),
      duration: duration ?? Duration.zero,
    );
    await FirebaseFirestore.instance.collection('users').doc(username).collection('voice_notes').doc(id).set(note.toMap());
  }

  void _playVoiceNote(VoiceNote note) async {
    if (_currentPlayingId == note.id && _isPlaying) {
      await _audioPlayer.pause();
      setState(() { _isPlaying = false; });
      return;
    }
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(note.localPath));
    setState(() {
      _isPlaying = true;
      _currentPlayingId = note.id;
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() { _isPlaying = false; });
    });
  }

  void _showVoiceNoteMenu(BuildContext context, VoiceNote note) {
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
                note.title = newTitle;
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
        title: Text('Rename'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text('Rename')),
        ],
      ),
    );
  }

  Future<void> _startFloatingRecording() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      print("Microphone permission denied");
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/${const Uuid().v4()}.m4a';
    await _recorder.start(const RecordConfig(), path: filePath);
    setState(() {
      _isFloatingRecording = true;
      _recordDuration = Duration.zero;
      _currentRecordingPath = filePath;
    });
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      setState(() {
        _recordDuration += Duration(seconds: 1);
      });
    });
  }

  Future<void> _stopFloatingRecordingAndSave() async {
    print('Attempting to stop recording...');
    String? path;
    try {
      path = await _recorder.stop();
      print('Recorder stopped, path: $path');
    } catch (e) {
      print('Error stopping recorder: $e');
    } finally {
      _timer?.cancel();
      setState(() {
        _isFloatingRecording = false;
      });
    }
    if (path == null) {
      print('No path returned from recorder.stop()');
      return;
    }
    try {
      final file = File(path);
      print('File exists: ${await file.exists()}');
      final duration = await _audioPlayer.setSourceDeviceFile(path).then((_) => _audioPlayer.getDuration());
      print('Duration: $duration');
      final id = const Uuid().v4();
      final now = DateTime.now();
      final title = DateFormat('yyyyMMdd_HHmmss').format(now);
      final note = VoiceNote(
        id: id,
        title: title,
        url: path,
        localPath: path,
        date: now,
        duration: duration ?? Duration.zero,
      );
      await Hive.box<VoiceNote>('voice_notes').add(note);
      print('Voice note added to Hive');
    } catch (e) {
      print('Error saving voice note: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDD5D1),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  // Header image
                  Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                        child: Container(
                          width: double.infinity,
                          height: 180,
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage('assets/vaultbg.png'),
                              fit: BoxFit.cover,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 25,
                        right: 30,
                        child: Column(
                          children: [
                            Material(
                              color: Color(0xFFFFD9D0),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () async {
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (context) => HomePage()),
                                    (route) => false,
                                  );
                                },
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Center(
                                    child: Icon(Icons.logout, color: Colors.pinkAccent, size: 25),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Stack(
                              children: [
                                // Outline
                                Text(
                                  'Logout',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 1.5
                                      ..color = Colors.white, // Outline color
                                  ),
                                ),
                                // Fill
                                Text(
                                  'Logout',
                                  style: TextStyle(
                                    color: Color(0xFFFFD9D0),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Vault and last viewed
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          'Vault',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Color(0xFFFFF7E9),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: FutureBuilder<String>(
                            future: getLastViewed(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return Text('Last viewed : ...', style: TextStyle(fontSize: 14, color: Colors.black87));
                              }
                              return Text(
                                'Last viewed : ${snapshot.data ?? 'Never'}',
                                style: TextStyle(fontSize: 14, color: Colors.black87),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Voice Notes Section
                  _SectionHeader(
                    icon: Icons.star,
                    text: '    The things you say today \n become memories tomorrow',
                    title: 'Voice Notes',
                    color: Color(0xFFFDCBB0),
                  ),
                  _VaultSectionCard(
                    child: Column(
                      children: [
                        _SearchBar(
                          onAdd: () async {
                            FilePickerResult? result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['mp3', 'm4a', 'wav', 'aac','opus','ogg'],
                            );
                            print('File picker result: $result');
                            if (result != null && result.files.single.path != null) {
                              print('Picked file path: ${result.files.single.path}');
                              final file = File(result.files.single.path!);
                              final id = const Uuid().v4();
                              final audioPlayer = AudioPlayer();
                              final duration = await audioPlayer.setSourceDeviceFile(file.path).then((_) => audioPlayer.getDuration());
                              final note = VoiceNote(
                                id: id,
                                title: capitalizeIfNeeded(result.files.single.name),
                                url: file.path,
                                localPath: file.path,
                                date: DateTime.now(),
                                duration: duration ?? Duration.zero,
                              );
                              await Hive.box<VoiceNote>('voice_notes').add(note);
                              print('Voice note added to Hive from file picker');
                            }
                          },
                          isRecording: _isRecording,
                          onChanged: (v) => setState(() => _voiceNoteSearch = v),
                        ),
                        SizedBox(height: 8),
                        ValueListenableBuilder(
                          valueListenable: Hive.box<VoiceNote>('voice_notes').listenable(),
                          builder: (context, Box<VoiceNote> box, _) {
                            final notes = box.values.toList().reversed.toList();
                            final filteredNotes = notes.where((n) => n.title.toLowerCase().contains(_voiceNoteSearch.toLowerCase())).toList();
                            if (filteredNotes.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(child: Text('No audio files uploaded')),
                              );
                            }
                            return Column(
                              children: [
                                ...filteredNotes.take(2).map((note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _VoiceNoteItem(
                                    note: note,
                                    isPlaying: _currentPlayingId == note.id && _isPlaying,
                                    onPlay: () => _playVoiceNote(note),
                                    onMenu: () => _showVoiceNoteMenu(context, note),
                                  ),
                                )),
                              ],
                            );
                          },
                        ),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ViewAllButton(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AllVoiceNotesPage(
                                      notes: Hive.box<VoiceNote>('voice_notes').values.toList().reversed.toList(),
                                      onPlay: (note) => _playVoiceNote(note),
                                      onMenu: (note) => _showVoiceNoteMenu(context, note),
                                      currentPlayingId: _currentPlayingId,
                                      isPlaying: _isPlaying,
                                    ),
                                  ),
                                );
                              },
                            ),
                            SizedBox(width: 20),
                            Column(
                              children: [
                                SizedBox(
                                  height: 48,
                                  width: 140,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (_isFloatingRecording) {
                                        _stopFloatingRecordingAndSave();
                                      } else {
                                        _startFloatingRecording();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE19378),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(_isFloatingRecording ? Icons.stop : Icons.mic, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text(_isFloatingRecording ? 'Stop' : 'Record', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_isFloatingRecording)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      _formatDuration(_recordDuration),
                                      style: TextStyle(
                                        color: Color.fromARGB(255, 234, 152, 115),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Images Section
                  _SectionHeader(
                    icon: Icons.star,
                    text: 'A picture that heals,A memory \n                  that hugs',
                    title: 'Images',
                    color: Color(0xFFFDCBB0),
                  ),
                  _VaultSectionCard(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
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
                            onChanged: (v) => setState(() => _imageSearch = v),
                          ),
                        ),
                        SizedBox(height: 8),
                        ValueListenableBuilder(
                          valueListenable: Hive.box<ImageNote>('image_notes').listenable(),
                          builder: (context, Box<ImageNote> box, _) {
                            final notes = box.values.toList().reversed.toList();
                            final filteredNotes = notes.where((n) => n.title.toLowerCase().contains(_imageSearch.toLowerCase())).toList();
                            if (filteredNotes.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(child: Text('No images uploaded')),
                              );
                            }
                            return Column(
                              children: [
                                ...filteredNotes.take(2).map((note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _ImageListItem(
                                    note: note,
                                    onMenu: () => _showImageMenu(context, note),
                                  ),
                                )),
                              ],
                            );
                          },
                        ),
                        SizedBox(height: 8),
                        _ViewAllButton(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ViewAllImagesPage()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Videos Section
                  _SectionHeader(
                    icon: Icons.star,
                    text: "Your life's best scenes, saved securely",
                    title: 'Videos',
                    color: Color(0xFFFDCBB0),
                  ),
                  _VaultSectionCard(
                    child: Column(
                      children: [
                        _SearchBar(
                          onAdd: () async {
                            FilePickerResult? result = await FilePicker.platform.pickFiles(
                              type: FileType.video,
                              allowMultiple: false,
                            );
                            if (result != null && result.files.single.path != null) {
                              final file = File(result.files.single.path!);
                              final id = const Uuid().v4();
                              final note = VideoNote(
                                id: id,
                                path: file.path,
                                title: capitalizeIfNeeded(result.files.single.name),
                                date: DateTime.now(),
                              );
                              await Hive.box<VideoNote>('video_notes').add(note);
                            }
                          },
                          onChanged: (v) => setState(() => _videoSearch = v),
                        ),
                        SizedBox(height: 8),
                        ValueListenableBuilder(
                          valueListenable: Hive.box<VideoNote>('video_notes').listenable(),
                          builder: (context, Box<VideoNote> box, _) {
                            final notes = box.values.toList().reversed.toList();
                            final filteredNotes = notes.where((n) => n.title.toLowerCase().contains(_videoSearch.toLowerCase())).toList();
                            if (filteredNotes.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(child: Text('No videos uploaded')),
                              );
                            }
                            return Column(
                              children: [
                                ...filteredNotes.take(2).map((note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _VideoListItem(
                                    note: note,
                                    onMenu: () => _showVideoMenu(context, note),
                                  ),
                                )),
                              ],
                            );
                          },
                        ),
                        SizedBox(height: 8),
                        _ViewAllButton(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ViewAllVideosPage()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '${twoDigits(d.inHours)}:$minutes:$seconds';
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String text;
  final String title;
  final Color color;
  const _SectionHeader({required this.icon, required this.text, required this.title, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 18, bottom: 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: Colors.amber),
                SizedBox(width: 4),
                Text(
                  text,
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
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

class _SearchBar extends StatelessWidget {
  final VoidCallback? onAdd;
  final bool isRecording;
  final Function(String)? onChanged;
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
          suffixIcon: IconButton(
            icon: Icon(isRecording ? Icons.stop : Icons.add, color: Color.fromARGB(255, 234, 152, 115), size: 22),
            onPressed: onAdd,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minHeight: 32, minWidth: 32),
          ),
        ),
        style: TextStyle(fontSize: 13),
        onChanged: onChanged,
      ),
    );
  }
}

class _VoiceNoteItem extends StatelessWidget {
  final VoiceNote note;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onMenu;
  const _VoiceNoteItem({required this.note, required this.isPlaying, required this.onPlay, required this.onMenu});
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
          IconButton(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Color.fromARGB(255, 234, 152, 115)),
            onPressed: onPlay,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title.length > 10
                      ? note.title.substring(0, 10) + '...'
                      : note.title,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(DateFormat('dd-MM-yy').format(note.date), style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Text(_formatDuration(note.duration), style: TextStyle(fontSize: 12, color: Colors.grey)),
          SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.more_vert, color: Colors.grey),
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds % 60)}';
  }
}

class _HorizontalList extends StatelessWidget {
  final List<Widget> items;
  const _HorizontalList({required this.items});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: 12),
        itemBuilder: (context, i) => items[i],
      ),
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
        color: Color(0xFFFFDED0),
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

class _VideoItem extends StatelessWidget {
  final String label;
  final String date;
  final String asset;
  const _VideoItem({required this.label, required this.date, required this.asset});
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Color(0xFFFDDED0),
            borderRadius: BorderRadius.circular(16),
            image: DecorationImage(
              image: AssetImage(asset),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Icon(Icons.play_circle_fill, color: Colors.black54, size: 32),
        Positioned(
          bottom: 0,
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
              Text(date, style: TextStyle(fontSize: 10, color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ViewAllButton({this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Center(
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE19378),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            elevation: 0,
          ),
          child: Text(
            'View All',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class AllVoiceNotesPage extends StatefulWidget {
  final List<VoiceNote> notes;
  final Function(VoiceNote) onPlay;
  final Function(VoiceNote) onMenu;
  final String? currentPlayingId;
  final bool isPlaying;
  const AllVoiceNotesPage({
    required this.notes,
    required this.onPlay,
    required this.onMenu,
    required this.currentPlayingId,
    required this.isPlaying,
    Key? key,
  }) : super(key: key);

  @override
  State<AllVoiceNotesPage> createState() => _AllVoiceNotesPageState();
}

class _AllVoiceNotesPageState extends State<AllVoiceNotesPage> {
  String _search = '';
  String? _currentPlayingId;
  bool _isPlaying = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _playVoiceNote(VoiceNote note) async {
    if (_currentPlayingId == note.id && _isPlaying) {
      await _audioPlayer.pause();
      setState(() { _isPlaying = false; });
      return;
    }
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(note.localPath));
    setState(() {
      _isPlaying = true;
      _currentPlayingId = note.id;
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() { _isPlaying = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = (widget.notes.toList()..sort((a, b) => b.date.compareTo(a.date)))
        .where((n) => n.title.toLowerCase().contains(_search.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 254, 230, 230),
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
                  Text('Voice Notes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
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
                    suffixIcon: IconButton(
                      icon: Icon(Icons.add, color: Color.fromARGB(255, 234, 152, 115), size: 22),
                      onPressed: null,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minHeight: 32, minWidth: 32),
                    ),
                  ),
                  style: TextStyle(fontSize: 13),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: _VaultSectionCard(
                  child: ListView.separated(
                    itemCount: filteredNotes.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (context, i) => _VoiceNoteItem(
                      note: filteredNotes[i],
                      isPlaying: _currentPlayingId == filteredNotes[i].id && _isPlaying,
                      onPlay: () => _playVoiceNote(filteredNotes[i]),
                      onMenu: () => widget.onMenu(filteredNotes[i]),
                    ),
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
              note.title = newTitle;
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
      title: Text('Rename'),
      content: TextField(controller: controller),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text('Rename')),
      ],
    ),
  );
}

@HiveType(typeId: 0)
class VoiceNote extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  String title;
  @HiveField(2)
  final String url;
  @HiveField(3)
  final String localPath;
  @HiveField(4)
  final DateTime date;
  @HiveField(5)
  final Duration duration;

  VoiceNote({
    required this.id,
    required this.title,
    required this.url,
    required this.localPath,
    required this.date,
    required this.duration,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'url': url,
    'localPath': localPath,
    'date': date.toIso8601String(),
    'duration': duration.inSeconds,
  };

  static VoiceNote fromMap(Map<String, dynamic> map) => VoiceNote(
    id: map['id'],
    title: map['title'],
    url: map['url'],
    localPath: map['localPath'],
    date: DateTime.parse(map['date']),
    duration: Duration(seconds: map['duration']),
  );
}

class VideoPlayerDialog extends StatefulWidget {
  final String videoPath;
  const VideoPlayerDialog({Key? key, required this.videoPath}) : super(key: key);

  @override
  _VideoPlayerDialogState createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<VideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isMuted = false;
  int _rotationTurns = 0;

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '${twoDigits(d.inHours)}:$minutes:$seconds';
  }

  void _goFullscreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPlayerPage(
          videoPath: widget.videoPath,
          initialRotation: _rotationTurns,
        ),
      ),
    );
    // Optionally, resume playback or update state after returning
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return AlertDialog(
          backgroundColor: Colors.black,
          content: _isInitialized
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                    SizedBox(height: 8),
                    _buildControls(),
                  ],
                )
              : SizedBox(
                  width: 200,
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isInitialized)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_controller.value.position),
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                _formatDuration(_controller.value.duration),
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        VideoProgressIndicator(_controller, allowScrubbing: true),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
            ),
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isMuted = !_isMuted;
                  _controller.setVolume(_isMuted ? 0 : 1);
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.fullscreen, color: Colors.white),
              onPressed: _goFullscreen,
            ),
          ],
        ),
      ],
    );
  }
}

class FullscreenVideoPlayerPage extends StatefulWidget {
  final String videoPath;
  final int initialRotation;
  const FullscreenVideoPlayerPage({Key? key, required this.videoPath, this.initialRotation = 0}) : super(key: key);

  @override
  State<FullscreenVideoPlayerPage> createState() => _FullscreenVideoPlayerPageState();
}

class _FullscreenVideoPlayerPageState extends State<FullscreenVideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isMuted = false;
  int _rotationTurns = 0;

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '${twoDigits(d.inHours)}:$minutes:$seconds';
  }

  @override
  void initState() {
    super.initState();
    _rotationTurns = widget.initialRotation;
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
        _controller.play();
      });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Center(
              child: _isInitialized
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: VideoPlayer(_controller),
                          ),
                        ),
                        _buildControls(),
                      ],
                    )
                  : Center(child: CircularProgressIndicator()),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isInitialized)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_controller.value.position),
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                _formatDuration(_controller.value.duration),
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        VideoProgressIndicator(_controller, allowScrubbing: true),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
            ),
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isMuted = !_isMuted;
                  _controller.setVolume(_isMuted ? 0 : 1);
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.fullscreen_exit, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

class _VideoListItem extends StatelessWidget {
  final VideoNote note;
  final VoidCallback onMenu;
  const _VideoListItem({required this.note, required this.onMenu});
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
              if (note.path.endsWith('.mp4')) {
                showDialog(
                  context: context,
                  builder: (_) => VideoPlayerDialog(videoPath: note.path),
                );
              } else {
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
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: note.path.endsWith('.mp4')
                ? FutureBuilder<Uint8List?>(
                    future: VideoThumbnail.thumbnailData(
                      video: note.path,
                      imageFormat: ImageFormat.PNG,
                      maxWidth: 128,
                      quality: 75,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                        return Image.memory(
                          snapshot.data!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        );
                      } else {
                        return Container(
                          width: 48,
                          height: 48,
                          color: Colors.black12,
                          child: Icon(Icons.videocam, color: Colors.grey, size: 32),
                        );
                      }
                    },
                  )
                : Image.file(
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
                Text(
                  '${note.date.day.toString().padLeft(2, '0')}-${note.date.month.toString().padLeft(2, '0')}-${note.date.year}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
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

void _showVideoMenu(BuildContext context, VideoNote note) {
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
              note.title = newTitle;
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

// Utility function to capitalize first letter if not numeric
String capitalizeIfNeeded(String input) {
  if (input.isEmpty) return input;
  if (double.tryParse(input[0]) != null) return input;
  return input[0].toUpperCase() + input.substring(1);
} 