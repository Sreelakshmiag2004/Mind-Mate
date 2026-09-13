import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'video_note.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
// PHASE14H: `_VaultVideo`/`_friendlyVideoMediaError` are duplicated here
// rather than imported from vault.dart — Dart privacy is per-file, so
// vault.dart's own leading-underscore declarations aren't visible here
// regardless, exactly the same reasoning as PHASE14F's
// viewall_images.dart. `videoContentTypeForFilename`/`kMaxVideoUploadBytes`
// are duplicated too (not reused via an import) to match this specific
// file pair's own pre-existing convention: unlike viewall_images.dart
// (which already had a dormant `import 'vault.dart'` to revive),
// viewall_videos.dart never imported vault.dart at all — introducing that
// relationship now would be a bigger change than duplicating two small
// pure functions, and `capitalizeIfNeeded` below is already fully
// duplicated between these two files on the same basis.
import 'core/network/api_exception.dart';
import 'data/models/media/media_asset_model.dart';
import 'data/repositories/media_repository.dart';
// PHASE14I-F: suppresses a migrated legacy Hive video from this page's own
// merged list — see legacy_media_reconciliation.dart's doc.
import 'data/services/legacy_media_reconciliation.dart';
import 'custom_snackbar.dart';

class ViewAllVideosPage extends StatefulWidget {
  const ViewAllVideosPage({Key? key}) : super(key: key);

  @override
  State<ViewAllVideosPage> createState() => _ViewAllVideosPageState();
}

class _ViewAllVideosPageState extends State<ViewAllVideosPage> {
  String _search = '';

  /// PHASE14H: this user's backend-hosted videos, newest first — loaded
  /// independently here (this page has its own `State` and always has,
  /// unlike PHASE14G's `AllVoiceNotesPage`; there is deliberately no
  /// shared/global media state anywhere in the app).
  List<MediaAssetModel> _remoteVideos = [];

  @override
  void initState() {
    super.initState();
    _loadRemoteVideos();
  }

  Future<void> _loadRemoteVideos() async {
    try {
      final page = await MediaRepository.instance.list(mediaType: 'video', limit: 100, offset: 0);
      if (!mounted) return;
      setState(() { _remoteVideos = page.items; });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyVideoMediaError(e), icon: Icons.error_outline);
    }
  }

  /// PHASE14H video creation — replaces the old direct
  /// `Hive.box<VideoNote>('video_notes').add(...)` call. See vault.dart's
  /// `_uploadVideo` for the full rationale; this is the same flow,
  /// independently implemented for this page's own state.
  Future<void> _uploadVideo(String pickedPath, String pickedFilename) async {
    final file = File(pickedPath);
    if (!await file.exists()) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't find that video on your device.", icon: Icons.error_outline);
      return;
    }

    final contentType = videoContentTypeForFilename(pickedFilename);
    if (contentType == null) {
      if (!mounted) return;
      showCustomSnackBar(context, 'Only MP4 videos can be uploaded right now.', icon: Icons.error_outline);
      return;
    }

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't read that video. Please try again.", icon: Icons.error_outline);
      return;
    }

    if (bytes.length > kMaxVideoUploadBytes) {
      if (!mounted) return;
      showCustomSnackBar(context, 'That video is too large (max 25MB).', icon: Icons.error_outline);
      return;
    }

    try {
      final created = await MediaRepository.instance.upload(
        fileBytes: bytes,
        filename: pickedFilename,
        contentType: contentType,
      );

      var result = created;
      try {
        result = await MediaRepository.instance.rename(mediaId: created.id, title: capitalizeIfNeeded(pickedFilename));
      } on ApiException {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Video uploaded, but its title could not be saved. You can rename it from the menu.',
            icon: Icons.info_outline,
          );
        }
      }

      if (!mounted) return;
      setState(() { _remoteVideos = [result, ..._remoteVideos]; });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyVideoMediaError(e), icon: Icons.error_outline);
    }
  }

  Future<void> _renameVideo(_VaultVideo item, String newTitle) async {
    if (item.remote != null) {
      try {
        final updated = await MediaRepository.instance.rename(mediaId: item.remote!.id, title: newTitle);
        if (!mounted) return;
        setState(() {
          _remoteVideos = _remoteVideos.map((m) => m.id == updated.id ? updated : m).toList();
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        showCustomSnackBar(context, _friendlyVideoMediaError(e), icon: Icons.error_outline);
      }
      return;
    }
    // Legacy Hive item — unchanged from the pre-PHASE14H behavior.
    item.legacy!.title = capitalizeIfNeeded(newTitle);
    await item.legacy!.save();
  }

  Future<void> _deleteVideo(_VaultVideo item) async {
    if (item.remote != null) {
      try {
        await MediaRepository.instance.delete(item.remote!.id);
        if (!mounted) return;
        setState(() {
          _remoteVideos = _remoteVideos.where((m) => m.id != item.remote!.id).toList();
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        showCustomSnackBar(context, _friendlyVideoMediaError(e), icon: Icons.error_outline);
      }
      return;
    }
    // Legacy Hive item — unchanged from the pre-PHASE14H behavior; see
    // PHASE14H implementation report, "Delete flow" limitation.
    await item.legacy!.delete();
  }

  void _showVideoMenu(BuildContext context, _VaultVideo item) {
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
              final newTitle = await _showRenameDialog(context, item.title);
              if (newTitle != null && newTitle.isNotEmpty) {
                await _renameVideo(item, newTitle);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text('Delete'),
            onTap: () async {
              Navigator.pop(context);
              await _deleteVideo(item);
            },
          ),
        ],
      ),
    );
  }

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
                    await _uploadVideo(result.files.single.path!, result.files.single.name);
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
                      // PHASE14I-F: a legacy video whose migrated backend
                      // counterpart already exists in _remoteVideos is
                      // left out of `merged` here — the Hive record
                      // itself is untouched (box.values is never written
                      // to). See legacy_media_reconciliation.dart.
                      final unmigratedLegacy = suppressMigratedLegacyItems(
                        legacyItems: box.values.toList(),
                        remoteItems: _remoteVideos,
                        kind: LegacyMediaKind.video,
                        legacyIdOf: (n) => n.id,
                      );
                      final merged = <_VaultVideo>[
                        ..._remoteVideos.map((m) => _VaultVideo.remote(m)),
                        ...unmigratedLegacy.map((n) => _VaultVideo.legacy(n)),
                      ]..sort((a, b) => b.date.compareTo(a.date));
                      final filtered = merged
                          .where((item) => item.title.toLowerCase().contains(_search.toLowerCase()))
                          .toList();
                      if (filtered.isEmpty) {
                        return const Center(child: Text('No videos uploaded'));
                      }
                      return ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8),
                        itemBuilder: (context, i) => _VideoListItem(
                          key: ValueKey(filtered[i].key),
                          item: filtered[i],
                          onMenu: () => _showVideoMenu(context, filtered[i]),
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
  /// A local legacy Hive video's path. Exactly one of [videoPath]/
  /// [networkUrl] must be given (PHASE14H) — same shape as vault.dart's
  /// own `VideoPlayerDialog`.
  final String? videoPath;
  final String? networkUrl;
  final Future<String?> Function()? onExpiredUrl;
  const VideoPlayerDialog({Key? key, this.videoPath, this.networkUrl, this.onExpiredUrl})
      : assert(
          (videoPath == null) != (networkUrl == null),
          'exactly one of videoPath/networkUrl must be given',
        ),
        super(key: key);

  @override
  _VideoPlayerDialogState createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<VideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isMuted = false;
  bool _failed = false;
  bool _hasRetried = false;
  int _rotationTurns = 0;
  String? _currentNetworkUrl;

  void _goFullscreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPlayerPage(
          videoPath: widget.videoPath,
          networkUrl: _currentNetworkUrl,
          initialRotation: _rotationTurns,
        ),
      ),
    );
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _currentNetworkUrl = widget.networkUrl;
    _controller = _currentNetworkUrl != null
        ? VideoPlayerController.networkUrl(Uri.parse(_currentNetworkUrl!))
        : VideoPlayerController.file(File(widget.videoPath!));
    _initialize();
  }

  /// PHASE14H: same one-retry-then-give-up shape as vault.dart's own
  /// `VideoPlayerDialog._initialize` — see that method's doc.
  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() { _isInitialized = true; });
      _controller.play();
    } catch (_) {
      if (_currentNetworkUrl != null && widget.onExpiredUrl != null && !_hasRetried) {
        _hasRetried = true;
        final freshUrl = await widget.onExpiredUrl!();
        await _controller.dispose();
        if (freshUrl == null) {
          if (mounted) setState(() { _failed = true; });
          return;
        }
        _currentNetworkUrl = freshUrl;
        _controller = VideoPlayerController.networkUrl(Uri.parse(freshUrl));
        await _initialize();
        return;
      }
      if (mounted) setState(() { _failed = true; });
    }
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
          content: _failed
              ? const SizedBox(
                  width: 220,
                  height: 100,
                  child: Center(
                    child: Text("Couldn't play this video.", style: TextStyle(color: Colors.white)),
                  ),
                )
              : _isInitialized
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
  final String? videoPath;
  final String? networkUrl;
  final int initialRotation;
  const FullscreenVideoPlayerPage({Key? key, this.videoPath, this.networkUrl, this.initialRotation = 0})
      : assert(
          (videoPath == null) != (networkUrl == null),
          'exactly one of videoPath/networkUrl must be given',
        ),
        super(key: key);

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
    _controller = widget.networkUrl != null
        ? VideoPlayerController.networkUrl(Uri.parse(widget.networkUrl!))
        : VideoPlayerController.file(File(widget.videoPath!));
    _controller.initialize().then((_) {
      if (!mounted) return;
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

/// PHASE14H: same shape as vault.dart's own `_VaultVideo` — file-private
/// on both sides (Dart privacy is per-file), so this is a deliberate,
/// small duplication rather than a shared import.
class _VaultVideo {
  const _VaultVideo.remote(MediaAssetModel this.remote) : legacy = null;
  const _VaultVideo.legacy(VideoNote this.legacy) : remote = null;

  final MediaAssetModel? remote;
  final VideoNote? legacy;

  String get title => legacy?.title ?? remote!.title ?? remote!.originalFilename ?? 'Untitled';
  DateTime get date => legacy?.date ?? remote!.createdAt;
  String get key => legacy != null ? 'legacy:${legacy!.id}' : 'remote:${remote!.id}';
}

String? videoContentTypeForFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  if (ext == 'mp4') return 'video/mp4';
  return null;
}

const int kMaxVideoUploadBytes = 25 * 1024 * 1024;

String _friendlyVideoMediaError(ApiException e) {
  if (e is ValidationException) {
    return "That video couldn't be saved — please check it and try again.";
  }
  if (e is NetworkException) {
    return "Couldn't reach the server. Check your connection and try again.";
  }
  if (e is UnauthorizedException) {
    return 'Your session has expired. Please log in again.';
  }
  if (e is NotFoundException) {
    return 'That video could not be found.';
  }
  if (e.statusCode == 413) {
    return 'That video is too large (max 25MB).';
  }
  if (e.statusCode == 415) {
    return 'Only MP4 videos can be uploaded right now.';
  }
  return 'Something went wrong with that video. Please try again.';
}

class _VideoListItem extends StatelessWidget {
  final _VaultVideo item;
  final VoidCallback onMenu;
  const _VideoListItem({super.key, required this.item, required this.onMenu});

  Future<void> _openRemoteVideo(BuildContext context) async {
    final mediaId = item.remote!.id;
    String? url;
    try {
      url = (await MediaRepository.instance.get(mediaId)).downloadUrl;
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showCustomSnackBar(context, _friendlyVideoMediaError(e), icon: Icons.error_outline);
      return;
    }
    if (url == null) {
      if (!context.mounted) return;
      showCustomSnackBar(context, "Couldn't play that video. Please try again.", icon: Icons.error_outline);
      return;
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => VideoPlayerDialog(
        networkUrl: url,
        onExpiredUrl: () async {
          try {
            return (await MediaRepository.instance.get(mediaId)).downloadUrl;
          } on ApiException {
            return null;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final legacy = item.legacy;
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
              if (legacy == null) {
                _openRemoteVideo(context);
                return;
              }
              // Legacy Hive item — unchanged from the pre-PHASE14H
              // behavior, including its pre-existing `.mp4`-only sniff.
              if (legacy.path.endsWith('.mp4')) {
                showDialog(
                  context: context,
                  builder: (_) => VideoPlayerDialog(videoPath: legacy.path),
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
                          File(legacy.path),
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
              child: legacy == null
                  ? Container(
                      width: 48,
                      height: 48,
                      color: Colors.black12,
                      child: Icon(Icons.videocam, color: Colors.grey, size: 32),
                    )
                  : legacy.path.endsWith('.mp4')
                  ? FutureBuilder<Uint8List?>(
                      future: VideoThumbnail.thumbnailData(
                        video: legacy.path,
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
                      File(legacy.path),
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
                  item.title.length > 10 ? item.title.substring(0, 10) + '...' : item.title,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${item.date.day.toString().padLeft(2, '0')}-${item.date.month.toString().padLeft(2, '0')}-${item.date.year}',
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
