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
// PHASE14F: the active IMAGE flow only (creation/display/rename/delete)
// now goes through MediaRepository (FastAPI/S3) instead of Hive — see
// _uploadImage/_loadRemoteImages/_ImageListItem below, and the PHASE14F
// implementation report. Voice notes and videos are untouched — they
// still read/write Hive exactly as before this phase.
import 'core/network/api_exception.dart';
import 'data/models/media/media_asset_model.dart';
import 'data/repositories/media_repository.dart';
import 'custom_snackbar.dart';
// PHASE14I-D: the Vault header's "migrate to cloud" button (see below)
// pushes this route. Nothing else in vault.dart references it — no
// migration logic is duplicated here, only the navigation call.
import 'legacy_media_migration_page.dart';
// PHASE14I-F: suppresses a legacy Hive item from the merged lists below
// once a valid migrated backend counterpart exists — see that file's own
// doc for the full display-reconciliation contract. Also brings
// LegacyMediaKind into scope (re-exported from the migration service).
import 'data/services/legacy_media_reconciliation.dart';
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

  /// PHASE14F: this user's backend-hosted images (`GET /media?media_type=
  /// image`), newest first. Populated once in [initState] and refreshed
  /// after every successful upload/rename/delete — there is no shared/
  /// global media state anywhere in the app (deliberately, per the
  /// PHASE14F spec: no Provider/Riverpod/Bloc), so `ViewAllImagesPage`
  /// loads its own independent copy the same way.
  List<MediaAssetModel> _remoteImages = [];

  /// PHASE14G: this user's backend-hosted voice notes (`GET /media?
  /// media_type=voice`), newest first — same pattern as [_remoteImages].
  /// A recording or an imported audio file is added here (never to Hive)
  /// once its upload actually succeeds; existing Hive `voice_notes` are
  /// untouched and keep showing up via `_VoiceItem.legacy`.
  List<MediaAssetModel> _remoteVoiceNotes = [];

  /// PHASE14H: this user's backend-hosted videos (`GET /media?media_type=
  /// video`), newest first — same pattern as [_remoteImages]/
  /// [_remoteVoiceNotes]. Every item here is guaranteed `video/mp4` (the
  /// only content type the backend's upload allow-list accepts for video
  /// — PHASE14D audit report, Section 2), unlike a legacy Hive
  /// `VideoNote`, whose `path` extension is never actually verified.
  List<MediaAssetModel> _remoteVideos = [];

  @override
  void initState() {
    super.initState();
    _loadRemoteImages();
    _loadRemoteVoiceNotes();
    _loadRemoteVideos();
  }

  /// `GET /media?media_type=voice` via [MediaRepository] — see
  /// [_remoteVoiceNotes]'s own doc.
  Future<void> _loadRemoteVoiceNotes() async {
    try {
      final page = await MediaRepository.instance.list(mediaType: 'voice', limit: 100, offset: 0);
      if (!mounted) return;
      setState(() { _remoteVoiceNotes = page.items; });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyVoiceMediaError(e), icon: Icons.error_outline);
    }
  }

  /// `GET /media?media_type=video` via [MediaRepository] — see
  /// [_remoteVideos]'s own doc.
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

  /// `GET /media?media_type=image` via [MediaRepository] — see
  /// [_remoteImages]'s own doc. A failure here (network/5xx/401) leaves
  /// [_remoteImages] at whatever it was before (empty on first load) and
  /// surfaces a friendly error; it never silently pretends the list is
  /// empty or crashes the page.
  Future<void> _loadRemoteImages() async {
    try {
      final page = await MediaRepository.instance.list(mediaType: 'image', limit: 100, offset: 0);
      if (!mounted) return;
      setState(() { _remoteImages = page.items; });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyImageMediaError(e), icon: Icons.error_outline);
    }
  }

  /// PHASE14F image creation — replaces the old direct
  /// `Hive.box<ImageNote>('image_notes').add(...)` call. New images are no
  /// longer written to Hive at all; they exist only as a backend
  /// [MediaAssetModel] from this
  /// point on (pre-existing Hive `image_notes` are untouched and keep
  /// showing up via [_VaultImage.legacy] — see that class's doc).
  ///
  /// Order of operations, matching the PHASE14F spec exactly: read bytes
  /// -> determine content type -> size check -> `POST /media/upload` ->
  /// `PATCH` the same title the old Hive flow always set from the picked
  /// filename (the upload endpoint itself has no title field). The image
  /// is only ever added to [_remoteImages] (i.e., considered "created")
  /// once the upload itself has actually succeeded — never optimistically,
  /// and never on a failed upload.
  Future<void> _uploadImage(String pickedPath, String pickedFilename) async {
    final file = File(pickedPath);
    if (!await file.exists()) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't find that image on your device.", icon: Icons.error_outline);
      return;
    }

    final contentType = imageContentTypeForFilename(pickedFilename);
    if (contentType == null) {
      if (!mounted) return;
      showCustomSnackBar(context, "That file type isn't supported.", icon: Icons.error_outline);
      return;
    }

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't read that image. Please try again.", icon: Icons.error_outline);
      return;
    }

    // Client-side pre-check only, matching the backend's own default
    // 25MB limit (PHASE14D audit report, Section 2) — the backend's 413
    // remains the actual authority; this just avoids a wasted upload
    // attempt for an obviously oversized file.
    if (bytes.length > kMaxImageUploadBytes) {
      if (!mounted) return;
      showCustomSnackBar(context, 'That image is too large (max 25MB).', icon: Icons.error_outline);
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
        // The image itself is safely uploaded — only the title failed to
        // save. Shown as its own, distinct message rather than treated as
        // a failed upload (it isn't one): the user can retry the rename
        // from the item's own menu.
        if (mounted) {
          showCustomSnackBar(
            context,
            'Image uploaded, but its title could not be saved. You can rename it from the menu.',
            icon: Icons.info_outline,
          );
        }
      }

      if (!mounted) return;
      setState(() { _remoteImages = [result, ..._remoteImages]; });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyImageMediaError(e), icon: Icons.error_outline);
    }
  }

  /// PHASE14F rename — [item] may be backend-hosted or a pre-existing
  /// legacy Hive record; exactly one path runs, never both.
  Future<void> _renameImage(_VaultImage item, String newTitle) async {
    if (item.remote != null) {
      try {
        final updated = await MediaRepository.instance.rename(mediaId: item.remote!.id, title: newTitle);
        if (!mounted) return;
        setState(() {
          _remoteImages = _remoteImages.map((m) => m.id == updated.id ? updated : m).toList();
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        showCustomSnackBar(context, _friendlyImageMediaError(e), icon: Icons.error_outline);
      }
      return;
    }
    // Legacy Hive item — unchanged from the pre-PHASE14F behavior.
    item.legacy!.title = newTitle;
    await item.legacy!.save();
  }

  /// PHASE14F delete — same remote/legacy split as [_renameImage]. A
  /// legacy item has no reliable backend media id (see PHASE14F spec,
  /// "Delete flow"), so it is deleted locally exactly as before; this is
  /// a deliberate, documented limitation, not an oversight — see the
  /// PHASE14F implementation report.
  Future<void> _deleteImage(_VaultImage item) async {
    if (item.remote != null) {
      try {
        await MediaRepository.instance.delete(item.remote!.id);
        if (!mounted) return;
        setState(() {
          _remoteImages = _remoteImages.where((m) => m.id != item.remote!.id).toList();
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        showCustomSnackBar(context, _friendlyImageMediaError(e), icon: Icons.error_outline);
      }
      return;
    }
    // Legacy Hive item — unchanged from the pre-PHASE14F behavior (only
    // removes the Hive record; the underlying file on disk is untouched,
    // exactly as it always was — see PHASE14D audit report, Section 1).
    await item.legacy!.delete();
  }

  /// PHASE14F: now an instance method (was a bare top-level function
  /// taking an `ImageNote`) so Rename/Delete can go through
  /// [_renameImage]/[_deleteImage] and update this State's own
  /// [_remoteImages] on success — a bare top-level function has no way to
  /// call [setState].
  void _showImageMenu(BuildContext context, _VaultImage item) {
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
                await _renameImage(item, newTitle);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text('Delete'),
            onTap: () async {
              Navigator.pop(context);
              await _deleteImage(item);
            },
          ),
        ],
      ),
    );
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

  /// PHASE14G: [item] may be backend-hosted or a pre-existing legacy Hive
  /// record. A legacy item plays exactly as before
  /// (`DeviceFileSource(item.legacy!.localPath)`); a backend item resolves
  /// a fresh presigned URL and plays that via [_playRemoteVoiceNote] — see
  /// that method's own doc for the expired-URL retry behavior.
  void _playVoiceNote(_VoiceItem item) async {
    if (_currentPlayingId == item.key && _isPlaying) {
      await _audioPlayer.pause();
      setState(() { _isPlaying = false; });
      return;
    }
    await _audioPlayer.stop();
    if (item.legacy != null) {
      await _audioPlayer.play(DeviceFileSource(item.legacy!.localPath));
    } else {
      final started = await _playRemoteVoiceNote(_audioPlayer, item.remote!.id);
      if (!started) {
        if (!mounted) return;
        showCustomSnackBar(context, "Couldn't play that voice note. Please try again.", icon: Icons.error_outline);
        return;
      }
    }
    setState(() {
      _isPlaying = true;
      _currentPlayingId = item.key;
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() { _isPlaying = false; });
    });
  }

  /// PHASE14G rename — [item] may be backend-hosted or a pre-existing
  /// legacy Hive record; exactly one path runs, never both. Same shape as
  /// PHASE14F's `_renameImage`.
  Future<void> _renameVoiceNote(_VoiceItem item, String newTitle) async {
    if (item.remote != null) {
      try {
        final updated = await MediaRepository.instance.rename(mediaId: item.remote!.id, title: newTitle);
        if (!mounted) return;
        setState(() {
          _remoteVoiceNotes = _remoteVoiceNotes.map((m) => m.id == updated.id ? updated : m).toList();
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        showCustomSnackBar(context, _friendlyVoiceMediaError(e), icon: Icons.error_outline);
      }
      return;
    }
    // Legacy Hive item — unchanged from the pre-PHASE14G behavior.
    item.legacy!.title = newTitle;
    await item.legacy!.save();
  }

  /// PHASE14G delete — same remote/legacy split as [_renameVoiceNote]. A
  /// legacy item has no reliable backend media id, so it is deleted
  /// locally exactly as before — a deliberate, documented limitation, same
  /// as PHASE14F's `_deleteImage`.
  Future<void> _deleteVoiceNote(_VoiceItem item) async {
    if (item.remote != null) {
      try {
        await MediaRepository.instance.delete(item.remote!.id);
        if (!mounted) return;
        setState(() {
          _remoteVoiceNotes = _remoteVoiceNotes.where((m) => m.id != item.remote!.id).toList();
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        showCustomSnackBar(context, _friendlyVoiceMediaError(e), icon: Icons.error_outline);
      }
      return;
    }
    // Legacy Hive item — unchanged from the pre-PHASE14G behavior (only
    // removes the Hive record; the underlying file on disk is untouched).
    await item.legacy!.delete();
  }

  void _showVoiceNoteMenu(BuildContext context, _VoiceItem item) {
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
                await _renameVoiceNote(item, newTitle);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text('Delete'),
            onTap: () async {
              Navigator.pop(context);
              await _deleteVoiceNote(item);
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

  /// PHASE14G: replaces the old direct
  /// `Hive.box<VoiceNote>('voice_notes').add(...)` call. A finished
  /// recording is now uploaded through [MediaRepository] instead — it is
  /// no longer written to Hive at all.
  /// Recordings are always `.m4a` (the `record` package's default
  /// `RecordConfig()`, unchanged by this phase), which maps to backend
  /// content type `audio/mp4` — see [voiceContentTypeForFilename].
  Future<void> _stopFloatingRecordingAndSave() async {
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      // Matches the pre-PHASE14G behavior: a recorder-stop failure is
      // swallowed here (nothing was ever captured to upload).
    } finally {
      _timer?.cancel();
      setState(() {
        _isFloatingRecording = false;
      });
    }
    if (path == null) return;

    final now = DateTime.now();
    final title = DateFormat('yyyyMMdd_HHmmss').format(now);
    final duration = await _audioPlayer.setSourceDeviceFile(path).then((_) => _audioPlayer.getDuration());
    await _uploadVoiceNote(
      path: path,
      filename: '${const Uuid().v4()}.m4a',
      title: title,
      duration: duration,
    );
  }

  /// PHASE14G shared upload path for both a finished recording
  /// ([_stopFloatingRecordingAndSave]) and an imported audio file (the
  /// Voice Notes `_SearchBar.onAdd` below) — same order of operations as
  /// PHASE14F's `_uploadImage`: verify the file exists -> read bytes ->
  /// determine content type -> size check -> `POST /media/upload` ->
  /// `PATCH` the title (the upload endpoint itself has no title field) ->
  /// only then considered "created." [duration], when known, is sent as
  /// `duration_seconds` — the backend's own "client-reported, display-
  /// only" field for voice/video (PHASE14D audit report, Section 2).
  Future<void> _uploadVoiceNote({
    required String path,
    required String filename,
    required String title,
    Duration? duration,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't find that voice note on your device.", icon: Icons.error_outline);
      return;
    }

    final contentType = voiceContentTypeForFilename(filename);
    if (contentType == null) {
      if (!mounted) return;
      showCustomSnackBar(context, "That audio file type isn't supported.", icon: Icons.error_outline);
      return;
    }

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't read that voice note. Please try again.", icon: Icons.error_outline);
      return;
    }

    if (bytes.length > kMaxVoiceUploadBytes) {
      if (!mounted) return;
      showCustomSnackBar(context, 'That voice note is too large (max 25MB).', icon: Icons.error_outline);
      return;
    }

    try {
      final created = await MediaRepository.instance.upload(
        fileBytes: bytes,
        filename: filename,
        contentType: contentType,
        durationSeconds: duration?.inSeconds,
      );

      var result = created;
      try {
        result = await MediaRepository.instance.rename(mediaId: created.id, title: title);
      } on ApiException {
        // The voice note itself is safely uploaded — only the title
        // failed to save. Same treatment as PHASE14F's _uploadImage: shown
        // as its own, distinct message rather than a failed upload.
        if (mounted) {
          showCustomSnackBar(
            context,
            'Voice note uploaded, but its title could not be saved. You can rename it from the menu.',
            icon: Icons.info_outline,
          );
        }
      }

      if (!mounted) return;
      setState(() { _remoteVoiceNotes = [result, ..._remoteVoiceNotes]; });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyVoiceMediaError(e), icon: Icons.error_outline);
    }
  }

  /// PHASE14H video creation — replaces the old direct
  /// `Hive.box<VideoNote>('video_notes').add(...)` call. Same order of
  /// operations as PHASE14F/G's `_uploadImage`/`_uploadVoiceNote`: verify
  /// the file exists -> read bytes -> determine content type -> size
  /// check -> `POST /media/upload` -> `PATCH` the title -> only then
  /// considered "created." New videos are no longer written to Hive at
  /// all. Unlike images/voice, no duration is sent — `VideoNote` itself
  /// has never had a duration field, and nothing in the existing code
  /// measures one for a picked video.
  Future<void> _uploadVideo(String pickedPath, String pickedFilename) async {
    final file = File(pickedPath);
    if (!await file.exists()) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't find that video on your device.", icon: Icons.error_outline);
      return;
    }

    final contentType = videoContentTypeForFilename(pickedFilename);
    if (contentType == null) {
      // PHASE14H: the backend's upload allow-list accepts only
      // `video/mp4` (PHASE14D audit report, Section 2) — unlike
      // image/voice, there is no second supported format to fall back to,
      // so anything else is rejected clearly, before ever attempting an
      // upload, rather than left to a 415.
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

  /// PHASE14H rename — [item] may be backend-hosted or a pre-existing
  /// legacy Hive record; exactly one path runs, never both. Same shape as
  /// PHASE14F/G's `_renameImage`/`_renameVoiceNote`.
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

  /// PHASE14H delete — same remote/legacy split as [_renameVideo]. A
  /// legacy item has no reliable backend media id, so it is deleted
  /// locally exactly as before — same documented limitation as
  /// PHASE14F/G.
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
    // Legacy Hive item — unchanged from the pre-PHASE14H behavior (only
    // removes the Hive record; the underlying file on disk is untouched).
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
                        // PHASE14I-D: the entry point into the legacy Hive
                        // media migration screen — user-triggered only
                        // (nothing above this button ever navigates here on
                        // its own). See legacy_media_migration_page.dart;
                        // this button does nothing but push that route —
                        // no migration logic lives here.
                        IconButton(
                          key: const Key('migrateVaultButton'),
                          icon: Icon(Icons.cloud_upload_outlined, color: Colors.black87),
                          tooltip: 'Migrate legacy media to cloud',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => LegacyMediaMigrationPage()),
                            );
                          },
                        ),
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
                          // PHASE14G: an imported audio file now uploads to
                          // the backend via _uploadVoiceNote — it is no
                          // longer written to Hive. Duration is still
                          // measured the same pre-existing way
                          // (AudioPlayer.setSourceDeviceFile(...).
                          // getDuration()) and forwarded as
                          // duration_seconds, since that measurement is
                          // already reliable for an imported file — see the
                          // PHASE14G implementation report.
                          onAdd: () async {
                            FilePickerResult? result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['mp3', 'm4a', 'wav', 'aac','opus','ogg'],
                            );
                            if (result != null && result.files.single.path != null) {
                              final path = result.files.single.path!;
                              final filename = result.files.single.name;
                              final audioPlayer = AudioPlayer();
                              final duration = await audioPlayer.setSourceDeviceFile(path).then((_) => audioPlayer.getDuration());
                              await audioPlayer.dispose();
                              await _uploadVoiceNote(
                                path: path,
                                filename: filename,
                                title: capitalizeIfNeeded(filename),
                                duration: duration,
                              );
                            }
                          },
                          isRecording: _isRecording,
                          onChanged: (v) => setState(() => _voiceNoteSearch = v),
                        ),
                        SizedBox(height: 8),
                        // PHASE14G: merges backend-hosted voice notes
                        // (_remoteVoiceNotes) with pre-existing, not-yet-
                        // migrated Hive voice_notes (_VoiceItem.legacy)
                        // into one list, newest first — same pattern as
                        // PHASE14F's image merge.
                        ValueListenableBuilder(
                          valueListenable: Hive.box<VoiceNote>('voice_notes').listenable(),
                          builder: (context, Box<VoiceNote> box, _) {
                            // PHASE14I-F: a legacy voice note whose
                            // migrated backend counterpart already exists
                            // in _remoteVoiceNotes is left out of `merged`
                            // here — the Hive record itself is untouched
                            // (box.values is never written to).
                            final unmigratedLegacy = suppressMigratedLegacyItems(
                              legacyItems: box.values.toList(),
                              remoteItems: _remoteVoiceNotes,
                              kind: LegacyMediaKind.voice,
                              legacyIdOf: (n) => n.id,
                            );
                            final merged = <_VoiceItem>[
                              ..._remoteVoiceNotes.map((m) => _VoiceItem.remote(m)),
                              ...unmigratedLegacy.map((n) => _VoiceItem.legacy(n)),
                            ]..sort((a, b) => b.date.compareTo(a.date));
                            final filtered = merged
                                .where((item) => item.title.toLowerCase().contains(_voiceNoteSearch.toLowerCase()))
                                .toList();
                            if (filtered.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(child: Text('No audio files uploaded')),
                              );
                            }
                            return Column(
                              children: [
                                ...filtered.take(2).map((item) => Padding(
                                  key: ValueKey(item.key),
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _VoiceNoteItem(
                                    item: item,
                                    isPlaying: _currentPlayingId == item.key && _isPlaying,
                                    onPlay: () => _playVoiceNote(item),
                                    onMenu: () => _showVoiceNoteMenu(context, item),
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
                                // PHASE14G: same merge as above, snapshotted
                                // once at navigation time — preserves
                                // AllVoiceNotesPage's existing "receives a
                                // static list via its constructor" shape
                                // (unlike PHASE14F's ViewAllImagesPage,
                                // which independently reloads its own data)
                                // rather than redesigning it — see the
                                // PHASE14G implementation report,
                                // "Limitations."
                                // PHASE14I-F: same reconciliation as the
                                // compact list above, applied here too so
                                // "View all" never shows a migrated item
                                // twice either.
                                final unmigratedLegacy = suppressMigratedLegacyItems(
                                  legacyItems: Hive.box<VoiceNote>('voice_notes').values.toList(),
                                  remoteItems: _remoteVoiceNotes,
                                  kind: LegacyMediaKind.voice,
                                  legacyIdOf: (n) => n.id,
                                );
                                final merged = <_VoiceItem>[
                                  ..._remoteVoiceNotes.map((m) => _VoiceItem.remote(m)),
                                  ...unmigratedLegacy.map((n) => _VoiceItem.legacy(n)),
                                ]..sort((a, b) => b.date.compareTo(a.date));
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AllVoiceNotesPage(
                                      notes: merged,
                                      onPlay: (item) => _playVoiceNote(item),
                                      onMenu: (item) => _showVoiceNoteMenu(context, item),
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
                            // PHASE14F: picking an image now uploads it to
                            // the backend via _uploadImage — it is no
                            // longer written to Hive (see that method's
                            // doc).
                            onAdd: () async {
                              FilePickerResult? result = await FilePicker.platform.pickFiles(
                                type: FileType.image,
                                allowMultiple: false,
                              );
                              if (result != null && result.files.single.path != null) {
                                await _uploadImage(result.files.single.path!, result.files.single.name);
                              }
                            },
                            onChanged: (v) => setState(() => _imageSearch = v),
                          ),
                        ),
                        SizedBox(height: 8),
                        // PHASE14F: merges backend-hosted images
                        // (_remoteImages) with pre-existing, not-yet-
                        // migrated Hive image_notes (_VaultImage.legacy)
                        // into one list, newest first — see _VaultImage's
                        // own doc for why both still show up here.
                        ValueListenableBuilder(
                          valueListenable: Hive.box<ImageNote>('image_notes').listenable(),
                          builder: (context, Box<ImageNote> box, _) {
                            // PHASE14I-F: a legacy image whose migrated
                            // backend counterpart already exists in
                            // _remoteImages is left out of `merged` here —
                            // the Hive record itself is untouched
                            // (box.values is never written to).
                            final unmigratedLegacy = suppressMigratedLegacyItems(
                              legacyItems: box.values.toList(),
                              remoteItems: _remoteImages,
                              kind: LegacyMediaKind.image,
                              legacyIdOf: (n) => n.id,
                            );
                            final merged = <_VaultImage>[
                              ..._remoteImages.map((m) => _VaultImage.remote(m)),
                              ...unmigratedLegacy.map((n) => _VaultImage.legacy(n)),
                            ]..sort((a, b) => b.date.compareTo(a.date));
                            final filtered = merged
                                .where((item) => item.title.toLowerCase().contains(_imageSearch.toLowerCase()))
                                .toList();
                            if (filtered.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(child: Text('No images uploaded')),
                              );
                            }
                            return Column(
                              children: [
                                ...filtered.take(2).map((item) => Padding(
                                  key: ValueKey(item.key),
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _ImageListItem(
                                    item: item,
                                    onMenu: () => _showImageMenu(context, item),
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
                          // PHASE14H: a picked video now uploads to the
                          // backend via _uploadVideo — it is no longer
                          // written to Hive.
                          onAdd: () async {
                            FilePickerResult? result = await FilePicker.platform.pickFiles(
                              type: FileType.video,
                              allowMultiple: false,
                            );
                            if (result != null && result.files.single.path != null) {
                              await _uploadVideo(result.files.single.path!, result.files.single.name);
                            }
                          },
                          onChanged: (v) => setState(() => _videoSearch = v),
                        ),
                        SizedBox(height: 8),
                        // PHASE14H: merges backend-hosted videos
                        // (_remoteVideos) with pre-existing, not-yet-
                        // migrated Hive video_notes (_VaultVideo.legacy)
                        // into one list, newest first — same pattern as
                        // PHASE14F/G's image/voice merge.
                        ValueListenableBuilder(
                          valueListenable: Hive.box<VideoNote>('video_notes').listenable(),
                          builder: (context, Box<VideoNote> box, _) {
                            // PHASE14I-F: a legacy video whose migrated
                            // backend counterpart already exists in
                            // _remoteVideos is left out of `merged` here —
                            // the Hive record itself is untouched
                            // (box.values is never written to).
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
                                .where((item) => item.title.toLowerCase().contains(_videoSearch.toLowerCase()))
                                .toList();
                            if (filtered.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(child: Text('No videos uploaded')),
                              );
                            }
                            return Column(
                              children: [
                                ...filtered.take(2).map((item) => Padding(
                                  key: ValueKey(item.key),
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _VideoListItem(
                                    item: item,
                                    onMenu: () => _showVideoMenu(context, item),
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

/// PHASE14G: unifies a backend-migrated voice note ([remote]) and a
/// not-yet-migrated, Hive-only legacy voice note ([legacy]) into one
/// displayable/playable item — same shape as PHASE14F's `_VaultImage`.
/// Exactly one of the two is ever non-null. [key] is a stable widget/
/// playback identity only, never a value sent to the backend.
class _VoiceItem {
  const _VoiceItem.remote(MediaAssetModel this.remote) : legacy = null;
  const _VoiceItem.legacy(VoiceNote this.legacy) : remote = null;

  final MediaAssetModel? remote;
  final VoiceNote? legacy;

  String get title => legacy?.title ?? remote!.title ?? remote!.originalFilename ?? 'Untitled';
  DateTime get date => legacy?.date ?? remote!.createdAt;
  Duration get duration => legacy?.duration ?? Duration(seconds: remote!.durationSeconds ?? 0);
  String get key => legacy != null ? 'legacy:${legacy!.id}' : 'remote:${remote!.id}';
}

/// Maps a voice filename's extension to the exact content type the
/// backend's upload allow-list accepts for voice (PHASE14D audit report,
/// Section 2; `ALLOWED_CONTENT_TYPES` in
/// `backend/app/services/media_service.py`). Recordings are always
/// `.m4a`; imports are restricted by the file picker itself to
/// `mp3/m4a/wav/aac/opus/ogg` (see the Voice Notes `_SearchBar` below) —
/// every one of those maps to a real backend-supported type, so `null`
/// here would only ever occur for a name the picker's own filter should
/// already have excluded; handled anyway rather than assumed.
String? voiceContentTypeForFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'm4a':
      return 'audio/mp4';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'aac':
      return 'audio/aac';
    case 'opus':
      return 'audio/opus';
    case 'ogg':
      return 'audio/ogg';
    default:
      return null;
  }
}

/// A client-side pre-check only, matching the backend's own default
/// `max_upload_size_mb = 25` — same rationale as PHASE14F's
/// `kMaxImageUploadBytes`. Kept as its own, separately-named constant
/// (not a reuse of `kMaxImageUploadBytes`) so image code is never touched
/// by this phase.
const int kMaxVoiceUploadBytes = 25 * 1024 * 1024;

/// Maps a Vault-voice [ApiException] to a short, clean, user-facing
/// message — same approach as PHASE14F's `_friendlyImageMediaError`.
String _friendlyVoiceMediaError(ApiException e) {
  if (e is ValidationException) {
    return "That voice note couldn't be saved — please check it and try again.";
  }
  if (e is NetworkException) {
    return "Couldn't reach the server. Check your connection and try again.";
  }
  if (e is UnauthorizedException) {
    return 'Your session has expired. Please log in again.';
  }
  if (e is NotFoundException) {
    return 'That voice note could not be found.';
  }
  if (e.statusCode == 413) {
    return 'That voice note is too large (max 25MB).';
  }
  if (e.statusCode == 415) {
    return "That audio file type isn't supported.";
  }
  return 'Something went wrong with that voice note. Please try again.';
}

/// PHASE14G: resolves a fresh presigned download URL via `GET /media/{id}`
/// and starts playback on [player]. Presigned URLs expire (15 minutes,
/// PHASE14D audit report, Section 3/4), so this is resolved fresh on every
/// play, never cached. If playback itself fails on the first attempt
/// (e.g. the URL had already expired by the time the player requested the
/// bytes — a race the metadata fetch alone can't detect, since that fetch
/// succeeding only proves the media exists, not that the signature is
/// still valid when playback actually starts a moment later), this
/// re-fetches once and retries exactly once more; a second failure gives
/// up rather than looping. Shared by both `_VaultPageState` and
/// `_AllVoiceNotesPageState`, each of which owns its own [AudioPlayer].
/// Returns `true` iff playback actually started; shows no UI itself —
/// callers own their own mounted-check and error message.
Future<bool> _playRemoteVoiceNote(AudioPlayer player, String mediaId) async {
  Future<String?> resolveUrl() async {
    try {
      return (await MediaRepository.instance.get(mediaId)).downloadUrl;
    } on ApiException {
      return null;
    }
  }

  final url = await resolveUrl();
  if (url == null) return false;
  try {
    await player.play(UrlSource(url));
    return true;
  } catch (_) {
    final retryUrl = await resolveUrl();
    if (retryUrl == null) return false;
    try {
      await player.play(UrlSource(retryUrl));
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _VoiceNoteItem extends StatelessWidget {
  final _VoiceItem item;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onMenu;
  const _VoiceNoteItem({required this.item, required this.isPlaying, required this.onPlay, required this.onMenu});
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
                  item.title.length > 10
                      ? item.title.substring(0, 10) + '...'
                      : item.title,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(DateFormat('dd-MM-yy').format(item.date), style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Text(_formatDuration(item.duration), style: TextStyle(fontSize: 12, color: Colors.grey)),
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

/// PHASE14F: unifies a backend-migrated image ([remote]) and a not-yet-
/// migrated, Hive-only legacy image ([legacy]) into one displayable item.
/// Exactly one of the two is ever non-null. Every NEW image created from
/// this phase onward is [remote]; [legacy] exists purely so pre-existing
/// Hive `image_notes` recorded before this phase keep showing up and stay
/// renamable/deletable exactly as before — see the PHASE14F implementation
/// report, "temporary compatibility fallback for pre-existing Hive
/// images." [key] is a stable widget identity only, never a value sent to
/// the backend or used to address a remote item — see [_VaultPageState.
/// _renameImage]/[_deleteImage], which key off [remote]'s own server id.
class _VaultImage {
  const _VaultImage.remote(MediaAssetModel this.remote) : legacy = null;
  const _VaultImage.legacy(ImageNote this.legacy) : remote = null;

  final MediaAssetModel? remote;
  final ImageNote? legacy;

  String get title => legacy?.title ?? remote!.title ?? remote!.originalFilename ?? 'Untitled';
  DateTime get date => legacy?.date ?? remote!.createdAt;
  String get key => legacy != null ? 'legacy:${legacy!.id}' : 'remote:${remote!.id}';
}

/// Maps a picked image's filename extension to the exact content type the
/// backend's upload allow-list accepts for images (PHASE14D audit report,
/// Section 2; `ALLOWED_CONTENT_TYPES` in
/// `backend/app/services/media_service.py`) — `null` for anything else,
/// which PHASE14F treats as an unsupported type rather than guessing or
/// forwarding an unvalidated value to the backend.
String? imageContentTypeForFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    default:
      return null;
  }
}

/// A client-side pre-check only, matching the backend's own default
/// `max_upload_size_mb = 25` (PHASE14D audit report, Section 2) — the
/// backend's own 413 response remains the actual authority; this constant
/// just avoids a wasted upload attempt for an obviously oversized file.
const int kMaxImageUploadBytes = 25 * 1024 * 1024;

/// Maps a Vault-image [ApiException] to a short, clean, user-facing
/// message — same approach as `vault_password.dart`'s
/// `_friendlyVaultLockError`.
String _friendlyImageMediaError(ApiException e) {
  if (e is ValidationException) {
    return "That image couldn't be saved — please check it and try again.";
  }
  if (e is NetworkException) {
    return "Couldn't reach the server. Check your connection and try again.";
  }
  if (e is UnauthorizedException) {
    return 'Your session has expired. Please log in again.';
  }
  if (e is NotFoundException) {
    return 'That image could not be found.';
  }
  if (e.statusCode == 413) {
    return 'That image is too large (max 25MB).';
  }
  if (e.statusCode == 415) {
    return "That image type isn't supported.";
  }
  return 'Something went wrong with that image. Please try again.';
}

class _ImageListItem extends StatelessWidget {
  final _VaultImage item;
  final VoidCallback onMenu;
  const _ImageListItem({required this.item, required this.onMenu});

  static Widget _placeholder({Widget? child}) => Container(
    width: 48,
    height: 48,
    color: Colors.black12,
    child: child == null ? null : Center(child: child),
  );

  /// PHASE14F: a backend-hosted image has no local file — its bytes are
  /// only ever reachable via a freshly-resolved presigned `download_url`
  /// (`GET /media/{id}`), never cached or persisted (PHASE14D audit
  /// report, Section 3/4), so this is resolved fresh on every build.
  Widget _buildThumbnail() {
    if (item.legacy != null) {
      return Image.file(
        File(item.legacy!.path),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _placeholder(child: const Icon(Icons.broken_image, color: Colors.grey)),
      );
    }
    return FutureBuilder<MediaAssetModel>(
      future: MediaRepository.instance.get(item.remote!.id),
      builder: (context, snapshot) {
        final url = snapshot.data?.downloadUrl;
        if (snapshot.connectionState == ConnectionState.done && url != null) {
          return Image.network(
            url,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _placeholder(child: const Icon(Icons.broken_image, color: Colors.grey)),
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return _placeholder(child: const Icon(Icons.broken_image, color: Colors.grey));
        }
        return _placeholder(
          child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }

  void _openFullView(BuildContext context) {
    final Widget content;
    if (item.legacy != null) {
      content = Image.file(
        File(item.legacy!.path),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Padding(
          padding: EdgeInsets.all(32),
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        ),
      );
    } else {
      content = FutureBuilder<MediaAssetModel>(
        future: MediaRepository.instance.get(item.remote!.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator());
          }
          final url = snapshot.data?.downloadUrl;
          if (url == null) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
            );
          }
          return Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Padding(
              padding: EdgeInsets.all(32),
              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
            ),
          );
        },
      );
    }
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.black),
          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: content),
        ),
      ),
    );
  }

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
            onTap: () => _openFullView(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildThumbnail(),
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
                Text(DateFormat('dd-MM-yy').format(item.date), style: TextStyle(fontSize: 12, color: Colors.grey)),
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
  /// PHASE14G: a merged, pre-sorted snapshot of backend + legacy Hive
  /// voice notes, taken once at navigation time — see the "View All"
  /// button's `onTap` in `_VaultPageState.build`. Deliberately kept as the
  /// existing "receives a static list via its constructor" shape (this
  /// page has never independently queried Hive/the backend itself, unlike
  /// PHASE14F's `ViewAllImagesPage`) rather than redesigned — see the
  /// PHASE14G implementation report, "Limitations."
  final List<_VoiceItem> notes;
  final Function(_VoiceItem) onPlay;
  final Function(_VoiceItem) onMenu;
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

  /// PHASE14G: same remote/legacy split as `_VaultPageState._playVoiceNote`
  /// — this page owns its own [_audioPlayer], so this is its own copy
  /// rather than a shared instance method (the two `State`s are never
  /// alive at the same time in a way that could share one).
  void _playVoiceNote(_VoiceItem item) async {
    if (_currentPlayingId == item.key && _isPlaying) {
      await _audioPlayer.pause();
      setState(() { _isPlaying = false; });
      return;
    }
    await _audioPlayer.stop();
    if (item.legacy != null) {
      await _audioPlayer.play(DeviceFileSource(item.legacy!.localPath));
    } else {
      final started = await _playRemoteVoiceNote(_audioPlayer, item.remote!.id);
      if (!started) {
        if (!mounted) return;
        showCustomSnackBar(context, "Couldn't play that voice note. Please try again.", icon: Icons.error_outline);
        return;
      }
    }
    setState(() {
      _isPlaying = true;
      _currentPlayingId = item.key;
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
                      item: filteredNotes[i],
                      isPlaying: _currentPlayingId == filteredNotes[i].key && _isPlaying,
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

// PHASE14H: the standalone top-level `_showRenameDialog` that used to live
// here was only ever called by the old top-level `_showVideoMenu`; now
// that `_showVideoMenu` is a `_VaultPageState` instance method (needed so
// Rename/Delete can call `setState` — see that method's own doc), it
// resolves to `_VaultPageState._showRenameDialog` instead, and this
// duplicate became dead code. Removed rather than left orphaned.

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
  /// A local legacy Hive video's path. Exactly one of [videoPath]/
  /// [networkUrl] must be given (PHASE14H).
  final String? videoPath;

  /// A backend video's freshly-resolved presigned `download_url`
  /// (`MediaRepository.get(id)`), already obtained by the caller before
  /// opening this dialog.
  final String? networkUrl;

  /// PHASE14H: called at most once, only for a [networkUrl] source, if
  /// the first playback attempt fails — presigned URLs expire (PHASE14D
  /// audit report, Section 3/4), so a failure may just mean the one this
  /// dialog was opened with already had. Should return a freshly-resolved
  /// `download_url` (typically another `MediaRepository.get(id)` call),
  /// or `null` if that itself fails. `null` for a legacy [videoPath].
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

  /// The network URL currently backing [_controller] — starts as
  /// [VideoPlayerDialog.networkUrl] and is replaced with a freshly-
  /// resolved one after a single retry (see [_initialize]). `null` for a
  /// local [VideoPlayerDialog.videoPath].
  String? _currentNetworkUrl;

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
          networkUrl: _currentNetworkUrl,
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
    _currentNetworkUrl = widget.networkUrl;
    _controller = _currentNetworkUrl != null
        ? VideoPlayerController.networkUrl(Uri.parse(_currentNetworkUrl!))
        : VideoPlayerController.file(File(widget.videoPath!));
    _initialize();
  }

  /// PHASE14H: for a [VideoPlayerDialog.networkUrl] source, a failed
  /// first attempt triggers exactly one [VideoPlayerDialog.onExpiredUrl]
  /// re-fetch-and-retry; a second failure (or a local [videoPath], which
  /// never retries — a missing local file isn't something re-fetching a
  /// URL could fix) shows an error state rather than spinning forever.
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
  /// A local legacy Hive video's path. Exactly one of [videoPath]/
  /// [networkUrl] must be given (PHASE14H). Reached only from
  /// [VideoPlayerDialog]'s own fullscreen button, after that dialog's
  /// controller already initialized successfully — so, unlike
  /// [VideoPlayerDialog] itself, this page does not separately retry an
  /// expired URL; it simply reuses whatever source is already working.
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

/// PHASE14H: unifies a backend-migrated video ([remote]) and a not-yet-
/// migrated, Hive-only legacy video ([legacy]) into one displayable item
/// — same shape as PHASE14F/G's `_VaultImage`/`_VoiceItem`. Named
/// `_VaultVideo` rather than `_VideoItem`: this file already has an
/// existing, unrelated (and already-dead — see PHASE14D audit report,
/// Section 1) `_VideoItem` widget class, so that name was avoided rather
/// than colliding with it. Exactly one of [remote]/[legacy] is ever
/// non-null.
///
/// A [remote] item is guaranteed `video/mp4` — the only content type the
/// backend's upload allow-list accepts for video (PHASE14D audit report,
/// Section 2) — so [_VideoListItem] never needs the legacy
/// `path.endsWith('.mp4')` sniff for it; that pre-existing check (and its
/// documented mis-render for a non-`.mp4` legacy path) is left completely
/// unchanged for [legacy] items — see the PHASE14H implementation report,
/// "Important existing bug."
class _VaultVideo {
  const _VaultVideo.remote(MediaAssetModel this.remote) : legacy = null;
  const _VaultVideo.legacy(VideoNote this.legacy) : remote = null;

  final MediaAssetModel? remote;
  final VideoNote? legacy;

  String get title => legacy?.title ?? remote!.title ?? remote!.originalFilename ?? 'Untitled';
  DateTime get date => legacy?.date ?? remote!.createdAt;
  String get key => legacy != null ? 'legacy:${legacy!.id}' : 'remote:${remote!.id}';
}

/// Maps a video filename's extension to the exact content type the
/// backend's upload allow-list accepts — today just `video/mp4`
/// (PHASE14D audit report, Section 2; `ALLOWED_CONTENT_TYPES` in
/// `backend/app/services/media_service.py`). The existing picker
/// (`FileType.video`) is a broad OS-level filter that can return other
/// container formats; anything other than `.mp4` returns `null` here and
/// is rejected before ever attempting an upload — see `_uploadVideo`.
String? videoContentTypeForFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  if (ext == 'mp4') return 'video/mp4';
  return null;
}

/// A client-side pre-check only, matching the backend's own default
/// `max_upload_size_mb = 25` — same rationale as PHASE14F/G's
/// `kMaxImageUploadBytes`/`kMaxVoiceUploadBytes`. Its own, separately-
/// named constant so image/voice code is never touched by this phase.
const int kMaxVideoUploadBytes = 25 * 1024 * 1024;

/// Maps a Vault-video [ApiException] to a short, clean, user-facing
/// message — same approach as PHASE14F/G's `_friendlyImageMediaError`/
/// `_friendlyVoiceMediaError`.
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
  const _VideoListItem({required this.item, required this.onMenu});

  /// PHASE14H: resolves a fresh presigned `download_url` via
  /// `MediaRepository.get(id)` and opens [VideoPlayerDialog] with it,
  /// passing an `onExpiredUrl` callback that re-resolves the same way for
  /// that dialog's own single retry. On a resolution failure, shows a
  /// snackbar rather than opening a dialog that could never play anything.
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
              // behavior, including its pre-existing `.mp4`-only
              // video-vs-image-fallback sniff (see this file's own
              // `_VaultVideo` doc).
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
                  // PHASE14H: a remote item is always video/mp4 — no
                  // extension sniff needed — but, per the PHASE14D audit's
                  // own deferred decision (Section 9), generating a real
                  // thumbnail from a remote URL is out of scope for this
                  // phase; shown as the same static fallback icon the
                  // legacy path already uses while its own thumbnail is
                  // still loading, not a fetched image.
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

// Utility function to capitalize first letter if not numeric
String capitalizeIfNeeded(String input) {
  if (input.isEmpty) return input;
  if (double.tryParse(input[0]) != null) return input;
  return input[0].toUpperCase() + input.substring(1);
} 