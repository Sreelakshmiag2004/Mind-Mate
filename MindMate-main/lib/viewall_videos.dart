import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'video_note.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class ViewAllVideosPage extends StatefulWidget {
  const ViewAllVideosPage({Key? key}) : super(key: key);

  @override
  State<ViewAllVideosPage> createState() => _ViewAllVideosPageState();
}

class _ViewAllVideosPageState extends State<ViewAllVideosPage> {
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
                  Text('Videos', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SearchBar(
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
                    valueListenable: Hive.box<VideoNote>('video_notes').listenable(),
                    builder: (context, Box<VideoNote> box, _) {
                      final notes = (box.values.toList()..sort((a, b) => b.date.compareTo(a.date)))
                          .where((n) => n.title.toLowerCase().contains(_search.toLowerCase())).toList();
                      if (notes.isEmpty) {
                        return const Center(child: Text('No videos uploaded'));
                      }
                      return ListView.separated(
                        itemCount: notes.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8),
                        itemBuilder: (context, i) => _VideoListItem(
                          note: notes[i],
                          onMenu: () => _showVideoMenu(context, notes[i]),
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

  void _goFullscreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPlayerPage(
          videoPath: widget.videoPath,
          initialRotation: _rotationTurns,
        ),
      ),
    );
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

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '${twoDigits(d.inHours)}:$minutes:$seconds';
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

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '${twoDigits(d.inHours)}:$minutes:$seconds';
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
      title: Text('Rename'),
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